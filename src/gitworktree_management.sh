#!/usr/bin/env bash

git status >& /dev/null 
[[ $? -ne 0 ]] && echo 'Not a git repository' && exit 1

source "$(dirname $0)/helpers.sh"

if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
    echo 'Usage: ./gitworktree_management.sh workspace_dir worktree_abilitate
    '
    exit
fi

workspace_dir=$1
worktree_abilitate=$2

select_in_list() {
    prompt=$1
    elements=(${@:2})
    selected=$(for i in ${elements[@]}
    do
        echo $i
    done | fzf --prompt="$prompt")
    echo $selected
}

available_worktrees() {
    worktrees=()
    while read -r line; do
	worktree_branch=`awk '{print($3)}' <<< "$line" | tr -d '[]'`
	current_branch=`git branch --show-current`
	if [[ $worktree_branch != $current_branch ]]; then
	    worktrees+=("$worktree_branch")
	fi
    done <<< "`git worktree list`" 
    echo "${worktrees[@]}"
}

available_branches() {
    branches=()
    worktrees=($(available_worktrees))
    while read -r line; do
	branch=`awk '!/^[*+]/ {print $1}' <<< "$line" | sed 's/remotes\/origin\///g'`
	# Remove the HEAD and current branch for local remotes branches fetched
	current_branch=`git branch --show-current`
	if [[ $branch == $current_branch || $branch == "HEAD" || $branch == "" ]]; then
	    continue
	fi
	# check if the branch variable is already contained in branches array
	for tmp_branch in ${branches[@]}
	do
	    if [[ "$tmp_branch" == "$branch" ]]; then
		branch=""
		break
	    fi
	done
	if [[ $branch == "" ]]; then
	    continue
	fi
	# check if the branch variable is already checkout on a worktree
	for worktree in ${worktrees[@]}
	do
	    if [[ "$worktree" == "$branch" ]]; then
		branch=""
		break
	    fi
	done
	if [[ $branch == "" ]]; then
	    continue
	fi
	branches+=("$branch")
    done <<< "`git branch --all`" 
    echo "${branches[@]}"
}

add_new_worktree(){
    branch=$1
    current_worktree_number=`basename $(pwd) | sed 's/wt//g'`
    while read -r line; do
	worktree_path=`echo $line | awk '{print($1)}'`
	worktree_number=`basename $worktree_path | sed 's/wt//g'`
	if (( $worktree_number != $current_worktree_number )); then
	    break
	fi
	current_worktree_number=$((current_worktree_number+1))
    done <<< "`git worktree list`" 
    absolute_path=`pwd`
    new_worktree_path="${absolute_path/$(basename $(pwd))/}/wt$current_worktree_number"
    git worktree add $new_worktree_path $branch
    tmux new-window -n "wt$current_worktree_number" -c $new_worktree_path
}

move_to_worktree_window() {
    absolute_path=`git worktree list | grep $1 | awk '{print($1)}'`
    worktree_name=`basename $absolute_path`

    session_name=$(tmux display-message -p '#S')
    # Check if the window exists in the session
    if tmux list-windows -t "$session_name" | grep -q "$worktree_name"; then
	tmux select-window -t "$session_name:$worktree_name"
    else
	tmux new-window -n "$worktree_name" -c $absolute_path
    fi
}

move_action() {
    worktrees=($(available_worktrees))

    if [ ${#worktrees[@]} -eq 0 ]; then
	echo "This is the only worktree active"
	read -p "Do you want to do something else? [y/N] " selected
	if [[ $selected == "y" ]]; then
	    main "$@"
	fi
	exit 1
    fi

    worktree=`select_in_list 'Worktree>' "${worktrees[@]}"`

    if [ -z $worktree ]; then
	echo "No worktree exists or selected"
	exit 1
    fi

    move_to_worktree_window $worktree
}

add_action() {
    branches=($(available_branches))

    if [ ${#branches[@]} -eq 0 ]; then
	echo "No branch available"
	read -p "Do you want to do create a new one? [y/N] " selected
	if [[ $selected == "y" ]]; then
	    selected=""
	    until [[ $selected == "y" ]]; do
		read -p "Give me the name of the new branch> " branch
		read -p "Confirm this name of the branch? $branch [y/N] " selected
	    done
	    git branch $branch
	else
	    read -p "Do you want to do something else? [y/N] " selected
	    if [[ $selected == "y" ]]; then
		main "$@"
	    fi
	    exit 1
	fi
    else
	branch=`select_in_list 'Add worktree from>' "${branches[@]}"`

	if [ -z $branch ]; then
	    read -p "Do you want to do create a new one? [y/N] " selected
	    if [[ $selected == "y" ]]; then
		selected=""
		until [[ $selected == "y" ]]; do
		    read -p "Give me the name of the new branch> " branch
		    read -p "Confirm this name of the branch? $branch [y/N] " selected
		done
		git branch $branch
	    else
		read -p "Do you want to do something else? [y/N] " selected
		if [[ $selected == "y" ]]; then
		    main "$@"
		fi
		exit 1
	    fi
	fi
    fi

    worktrees=($(available_worktrees))

    for worktree in $worktrees
    do
	if [[ $worktree == $branch ]]; then
	    echo "Already a worktree"
	    read -p "What to move on that worktree? [y/N] " selected
	    if [[ $selected == "y" ]]; then
		move_to_worktree_window $branch
		exit 1
	    fi
	    read -p "Do you want to do something else? [y/N] " selected
	    if [[ $selected == "y" ]]; then
		main "$@"
	    fi
	    exit 1
	fi
    done

    add_new_worktree $branch
}

remove_action() {
    worktrees=($(available_worktrees))
    branch=`select_in_list 'Remove worktree>' "${worktrees[@]}"`
    worktree_path=`git worktree list | grep "\[$branch\]" | awk '{print($1)}'`
    read -p "Do you really want to remove $branch worktree? [y/N] " selected
    if [[ $selected == "y" ]]; then
	git worktree remove $worktree_path
	worktree_name=$(basename $worktree_path)
	session_name=$(tmux display-message -p '#S')
	tmux has-session -t $session_name:$worktree_name
	if [ $? == 0 ]; then
	    tmux kill-window -t $session_name:$worktree_name
	fi
    fi
    read -p "Do you want to do something else? [y/N] " selected
    if [[ $selected == "y" ]]; then
	main "$@"
    fi
    exit 1
}

main() {
    actions=(Move Add Remove Leave)
    action=$(for i in ${actions[@]}
    do
        echo $i
    done | fzf --prompt='What do you want to do>')
    
    case "$action" in
        "Move") 
	    move_action
    	;;
        "Add")
	    add_action
    	;;
        "Remove")
	    remove_action
    	;;
        *) echo "TODO: We are leaving"
    	;;
    esac
    
    exit 1
}

main "$@"

#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sync Obsidian Force Push
# @raycast.mode silent

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Try normal vault sync first; if sync fails, back up both sides and force local state upstream

VAULTS=("$HOME/Notes" "$HOME/second_brain")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
ERRORS=()
SYNCED=()

create_backups() {
    local mode="$1"
    local upstream="$2"
    local backup_stamp
    local local_backup
    local remote_backup

    backup_stamp=$(date +"%Y%m%d-%H%M%S")
    local_backup="backup/local-before-${mode}-${backup_stamp}"
    remote_backup="backup/remote-before-${mode}-${backup_stamp}"

    git branch -f "$local_backup" HEAD >/dev/null 2>&1 || return 1
    git branch -f "$remote_backup" "$upstream" >/dev/null 2>&1 || return 1

    printf "%s, %s" "$local_backup" "$remote_backup"
}

sync_vault() {
    local vault="$1"
    local name
    local upstream
    local remote
    local remote_branch
    local commit_output
    local pull_output
    local push_output
    local fetch_output
    local backup_refs
    local force_push_output

    name=$(basename "$vault")

    if [ ! -d "$vault/.git" ]; then
        ERRORS+=("$name: not a git repo")
        return
    fi

    cd "$vault" || {
        ERRORS+=("$name: can't cd")
        return
    }

    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null)
    if [ -z "$upstream" ]; then
        ERRORS+=("$name: no upstream branch")
        return
    fi

    remote=${upstream%%/*}
    remote_branch=${upstream#*/}

    git add -A
    if ! git diff --cached --quiet; then
        commit_output=$(git commit -m "obsidian sync $TIMESTAMP" --no-gpg-sign 2>&1)
        if [ $? -ne 0 ]; then
            ERRORS+=("$name: commit failed - $(echo "$commit_output" | tail -1)")
            return
        fi
    fi

    pull_output=$(git pull --rebase 2>&1)
    if [ $? -eq 0 ]; then
        push_output=$(git push 2>&1)
        if [ $? -eq 0 ]; then
            SYNCED+=("$name: synced")
            return
        fi
    fi

    git rebase --abort >/dev/null 2>&1

    fetch_output=$(git fetch "$remote" --prune 2>&1)
    if [ $? -ne 0 ]; then
        if [ -n "$push_output" ]; then
            ERRORS+=("$name: push failed - $(echo "$push_output" | tail -1); fetch failed - $(echo "$fetch_output" | tail -1)")
        else
            ERRORS+=("$name: pull failed - $(echo "$pull_output" | tail -1); fetch failed - $(echo "$fetch_output" | tail -1)")
        fi
        return
    fi

    backup_refs=$(create_backups "force-push" "$upstream")
    if [ $? -ne 0 ]; then
        ERRORS+=("$name: backup failed before force push")
        return
    fi

    force_push_output=$(git push --force "$remote" "HEAD:$remote_branch" 2>&1)
    if [ $? -ne 0 ]; then
        if [ -n "$push_output" ]; then
            ERRORS+=("$name: push failed - $(echo "$push_output" | tail -1); force push failed - $(echo "$force_push_output" | tail -1)")
        else
            ERRORS+=("$name: pull failed - $(echo "$pull_output" | tail -1); force push failed - $(echo "$force_push_output" | tail -1)")
        fi
        return
    fi

    SYNCED+=("$name: synced (forced from local, backups created)")
}

for vault in "${VAULTS[@]}"; do
    sync_vault "$vault"
done

if [ ${#ERRORS[@]} -eq 0 ]; then
    msg=$(printf "%s\n" "${SYNCED[@]}")
    osascript -e "display notification \"$msg\" with title \"Obsidian Force Push\" sound name \"Glass\""
else
    err_msg=$(printf "%s\n" "${ERRORS[@]}")
    ok_msg=$(printf "%s\n" "${SYNCED[@]}")
    full_msg="${ok_msg:+$ok_msg$'\n'}${err_msg}"
    osascript -e "display notification \"$full_msg\" with title \"Obsidian Force Push - Errors\" sound name \"Basso\""
fi

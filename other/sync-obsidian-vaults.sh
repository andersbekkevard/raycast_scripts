#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sync Obsidian Vaults
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔄

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Pull, stage, commit, and push changes for Notes and second_brain Obsidian vaults

VAULTS=("$HOME/Notes" "$HOME/second_brain")
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
ERRORS=()
SYNCED=()

sync_vault() {
    local vault="$1"
    local name
    name=$(basename "$vault")

    if [ ! -d "$vault/.git" ]; then
        ERRORS+=("$name: not a git repo")
        return
    fi

    cd "$vault" || { ERRORS+=("$name: can't cd"); return; }

    # Stage all local changes
    git add -A

    # Commit if anything to commit
    if ! git diff --cached --quiet; then
        git commit -m "obsidian sync $TIMESTAMP" --no-gpg-sign 2>/dev/null
        if [ $? -ne 0 ]; then
            ERRORS+=("$name: commit failed")
            return
        fi
    fi

    # Pull remote changes (rebase local commit on top)
    local pull_output
    pull_output=$(git pull --rebase 2>&1)
    if [ $? -ne 0 ]; then
        git rebase --abort 2>/dev/null
        ERRORS+=("$name: pull failed — $(echo "$pull_output" | tail -1)")
        return
    fi

    # Push
    local push_output
    push_output=$(git push 2>&1)
    if [ $? -ne 0 ]; then
        ERRORS+=("$name: push failed — $(echo "$push_output" | tail -1)")
        return
    fi

    SYNCED+=("$name: synced")
}

for vault in "${VAULTS[@]}"; do
    sync_vault "$vault"
done

# Build notification message
if [ ${#ERRORS[@]} -eq 0 ]; then
    msg=$(printf "%s\n" "${SYNCED[@]}")
    osascript -e "display notification \"$msg\" with title \"Obsidian Sync\" sound name \"Glass\""
else
    err_msg=$(printf "%s\n" "${ERRORS[@]}")
    ok_msg=$(printf "%s\n" "${SYNCED[@]}")
    full_msg="${ok_msg:+$ok_msg$'\n'}⚠️ ${err_msg}"
    osascript -e "display notification \"$full_msg\" with title \"Obsidian Sync — Errors\" sound name \"Basso\""
fi

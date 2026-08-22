#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Edit Selected in Neovim
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝
# @raycast.packageName Neovim

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Open the selected Finder or Desktop item in Neovim

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

find_nvim() {
    if command -v nvim >/dev/null 2>&1; then
        command -v nvim
        return
    fi

    for candidate in /opt/homebrew/bin/nvim /usr/local/bin/nvim "$HOME/.local/bin/nvim"; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
        fi
    done

    return 1
}

finder_selection() {
    local result

    for _ in 1 2 3 4 5; do
        if result="$(osascript 2>/dev/null <<'APPLESCRIPT'
tell application "Finder"
    set selectedItems to selection
    if selectedItems is {} then return ""
    return POSIX path of (item 1 of selectedItems as alias)
end tell
APPLESCRIPT
)"; then
            printf '%s\n' "$result"
            return 0
        fi
        sleep 0.1
    done

    return 1
}

shell_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

open_in_terminal() {
    local nvim_bin="$1"
    local selected_path="$2"
    local working_dir="$3"
    local command_text

    command_text="cd $(shell_quote "$working_dir") && exec $(shell_quote "$nvim_bin") $(shell_quote "$selected_path")"

    osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "$command_text"
end tell
APPLESCRIPT
}

open_in_ghostty() {
    local nvim_bin="$1"
    local selected_path="$2"
    local working_dir="$3"
    local command_text

    command_text="cd $(shell_quote "$working_dir") && exec $(shell_quote "$nvim_bin") $(shell_quote "$selected_path")"

    open -Fna Ghostty.app --args \
        --window-save-state=never \
        -e /bin/zsh -lc "$command_text"
}

selected_path="${1:-}"
if [ -z "$selected_path" ]; then
    if ! selected_path="$(finder_selection)"; then
        echo "Could not read Finder selection"
        exit 1
    fi
fi

if [ -z "$selected_path" ]; then
    echo "No Finder or Desktop item selected"
    exit 1
fi

if [ ! -e "$selected_path" ]; then
    echo "Selected item no longer exists: $selected_path"
    exit 1
fi

nvim_bin="$(find_nvim)" || {
    echo "Could not find nvim"
    exit 1
}

if [ -d "$selected_path" ]; then
    working_dir="$selected_path"
else
    working_dir="$(dirname "$selected_path")"
fi

if [ "${RAYCAST_NVIM_DRY_RUN:-}" = "1" ]; then
    command_text="cd $(shell_quote "$working_dir") && exec $(shell_quote "$nvim_bin") $(shell_quote "$selected_path")"
    printf 'nvim=%s\nselected=%s\nworking_dir=%s\ncommand=%s\n' \
        "$nvim_bin" \
        "$selected_path" \
        "$working_dir" \
        "$command_text"
    exit 0
fi

if [ -d "/Applications/Ghostty.app" ]; then
    open_in_ghostty "$nvim_bin" "$selected_path" "$working_dir"
else
    open_in_terminal "$nvim_bin" "$selected_path" "$working_dir"
fi

echo "$selected_path"

#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Generate History Scripts
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⚙️

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Regenerates all focus scripts from focus-configs.json with history support

# Metascript to generate focus scripts with optional browser history support
# This script generates all focus scripts from a single template
#
# Usage: ./generate-history-scripts.sh
#
# To add a new focus script:
# 1. Edit focus-configs.json and add a new entry
# 2. Format: {"name": "...", "title": "...", "icon": "...", "url_patterns": [...], "default_url": "...", "use_history": true/false}
# 3. Run this script to regenerate all focus scripts
#
# The generated scripts support:
# - Browser history lookup (when use_history: true)
# - Hardcoded default URLs (when use_history: false)

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/focus-configs.json"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Read configs from JSON file using Python
# Convert JSON array to bash array format: "name|title|icon|url_pattern1 url_pattern2|default_url|use_history"
export CONFIG_FILE
configs=()
while IFS= read -r line; do
    configs+=("$line")
done < <(python3 <<'PYTHON_EOF'
import json
import sys
import os

config_file = os.environ.get('CONFIG_FILE')
if not config_file:
    print("Error: CONFIG_FILE environment variable not set", file=sys.stderr)
    sys.exit(1)

try:
    with open(config_file, 'r', encoding='utf-8') as f:
        configs = json.load(f)
    
    for config in configs:
        name = config.get('name', '')
        title = config.get('title', '')
        icon = config.get('icon', '')
        url_patterns = ' '.join(config.get('url_patterns', []))
        default_url = config.get('default_url', '')
        use_history = config.get('use_history', False)
        # Convert boolean to lowercase string for bash comparison
        use_history_str = 'true' if use_history else 'false'
        print(f'{name}|{title}|{icon}|{url_patterns}|{default_url}|{use_history_str}')
except Exception as e:
    print(f'Error reading config file: {e}', file=sys.stderr)
    sys.exit(1)
PYTHON_EOF
)

# Check if we got any configs
if [ ${#configs[@]} -eq 0 ]; then
    echo "Error: No configs found in $CONFIG_FILE"
    exit 1
fi

# Generate a function to get URL from history (if use_history is true)
generate_history_function() {
    local url_patterns="$1"
    local default_url="$2"
    
    # Build SQL WHERE clause for URL patterns
    local where_clause=""
    local first=true
    for pattern in $url_patterns; do
        if [ "$first" = true ]; then
            where_clause="url LIKE '%${pattern}%'"
            first=false
        else
            where_clause="${where_clause} OR url LIKE '%${pattern}%'"
        fi
    done
    
    # Escape single quotes in default_url for bash
    local escaped_default_url="${default_url//\'/\'\\\'\'}"
    
    # Use quoted heredoc delimiter to prevent variable expansion, then replace placeholders
    local func_output=$(cat <<'HISTORY_FUNC_EOF'
# Function to get most recent URL from Comet history
get_most_recent_url() {
    local history_db="$HOME/Library/Application Support/Comet/Default/History"
    local temp_history="/tmp/comet_history_temp_$$.db"
    
    # Check if history database exists
    if [ ! -f "$history_db" ]; then
        echo "DEFAULT_URL_PLACEHOLDER"
        return
    fi
    
    # Copy history DB to avoid lock issues (browser may have it locked)
    if ! cp "$history_db" "$temp_history" 2>/dev/null; then
        echo "DEFAULT_URL_PLACEHOLDER"
        return
    fi
    
    # Query for most recent matching URL
    # Filter out common non-content pages
    local most_recent_url
    most_recent_url=$(sqlite3 "$temp_history" \
        "SELECT url FROM urls 
         WHERE (WHERE_CLAUSE_PLACEHOLDER)
         AND url NOT LIKE '%/Pages/Auth/Login.aspx%'
         AND url NOT LIKE '%/Pages/Auth/Logout.aspx%'
         ORDER BY last_visit_time DESC 
         LIMIT 1;" 2>/dev/null)
    
    # Clean up temp file
    rm -f "$temp_history"
    
    # Return found URL or default
    if [ -n "$most_recent_url" ]; then
        echo "$most_recent_url"
    else
        echo "DEFAULT_URL_PLACEHOLDER"
    fi
}
HISTORY_FUNC_EOF
)
    
    # Replace placeholders with actual values
    func_output="${func_output//DEFAULT_URL_PLACEHOLDER/${escaped_default_url}}"
    func_output="${func_output//WHERE_CLAUSE_PLACEHOLDER/${where_clause}}"
    
    echo "$func_output"
}

# Generate a focus script
generate_script() {
    local name="$1"
    local title="$2"
    local icon="$3"
    local url_patterns="$4"
    local default_url="$5"
    local use_history="$6"
    
    # Build URL condition for AppleScript (for activeTabURL check)
    local active_url_condition=""
    local first=true
    for pattern in $url_patterns; do
        if [ "$first" = true ]; then
            active_url_condition="activeTabURL contains \"$pattern\""
            first=false
        else
            active_url_condition="${active_url_condition} or activeTabURL contains \"$pattern\""
        fi
    done
    
    # Build URL condition for AppleScript (for currentTabURL check)
    local current_url_condition=""
    first=true
    for pattern in $url_patterns; do
        if [ "$first" = true ]; then
            current_url_condition="currentTabURL contains \"$pattern\""
            first=false
        else
            current_url_condition="${current_url_condition} or currentTabURL contains \"$pattern\""
        fi
    done
    
    # Build URL condition for AppleScript (for tabURL check)
    local tab_url_condition=""
    first=true
    for pattern in $url_patterns; do
        if [ "$first" = true ]; then
            tab_url_condition="tabURL contains \"$pattern\""
            first=false
        else
            tab_url_condition="${tab_url_condition} or tabURL contains \"$pattern\""
        fi
    done
    
    # Determine how to get the target URL and which template to use
    local url_retrieval_code=""
    local applescript_url_var=""
    local heredoc_delimiter=""
    local make_tab_url_prop=""
    
    if [ "$use_history" = "true" ]; then
        # Generate history function and call it
        url_retrieval_code=$(generate_history_function "$url_patterns" "$default_url")
        url_retrieval_code="${url_retrieval_code}"$'\n'$'\n'"# Get the target URL from history"
        url_retrieval_code="${url_retrieval_code}"$'\n'"TARGET_URL=\$(get_most_recent_url)"
        # Use variable interpolation - $TARGET_URL will be expanded by bash when script runs
        local dollar='$'
        applescript_url_var="set targetURL to \"${dollar}TARGET_URL\""
        heredoc_delimiter="APPLESCRIPT_EOF"
        make_tab_url_prop="{URL:targetURL}"
    else
        # Match old generator exactly: quoted heredoc, no targetURL variable, hardcoded URL
        heredoc_delimiter="'APPLESCRIPT_EOF'"
        local escaped_default_url="${default_url//\"/\\\"}"
        make_tab_url_prop="{URL:\"${escaped_default_url}\"}"
    fi
    
    cat > "${name}-focus.sh" <<EOF
#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ${title}
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ${icon}

# Documentation:
# @raycast.author Anders Bekkevard
EOF
    
    # Add history function code only if use_history is true
    if [ "$use_history" = "true" ]; then
        cat >> "${name}-focus.sh" <<EOF

${url_retrieval_code}
EOF
    else
        # Add blank line to match old generator format
        cat >> "${name}-focus.sh" <<EOF

EOF
    fi
    
    cat >> "${name}-focus.sh" <<EOF
# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, focus ${title} tab or open new tab
    osascript <<${heredoc_delimiter}
tell application "Comet"
EOF
    
    # Add targetURL variable only if use_history is true
    if [ "$use_history" = "true" ]; then
        cat >> "${name}-focus.sh" <<EOF
    ${applescript_url_var}
EOF
    fi
    
    cat >> "${name}-focus.sh" <<EOF
    set targetWindowIndex to -1
    set targetTabIndex to -1
    set foundTab to false
    set currentTabURL to ""
    set currentWindowIndex to -1
    set currentTabIndex to -1
    set anyMatchingTabFound to false
    
    -- Get current active tab info first
    if (count of windows) > 0 then
        try
            set currentTabURL to URL of active tab of window 1
            set currentWindowIndex to 1
            set currentTabIndex to active tab index of window 1
        end try
    end if
    
    -- Check if current tab matches the URL pattern
    set currentTabMatches to false
    if currentTabURL is not "" then
        if ${current_url_condition} then
            set currentTabMatches to true
            set anyMatchingTabFound to true
        end if
    end if
    
    -- Collect all matching tabs in left-to-right order (window by window, tab by tab)
    set matchingTabs to {}
    set currentTabPosition to -1
    
    repeat with w from 1 to (count of windows)
        set windowTabs to tabs of window w
        repeat with t from 1 to (count of windowTabs)
            try
                set tabURL to URL of tab t of window w
                if ${tab_url_condition} then
                    set end of matchingTabs to {windowIndex:w, tabIndex:t}
                    set anyMatchingTabFound to true
                    -- Check if this is the current tab
                    if currentWindowIndex is w and currentTabIndex is t then
                        set currentTabPosition to (count of matchingTabs)
                    end if
                end if
            end try
        end repeat
    end repeat
    
    -- Determine which tab to switch to
    if (count of matchingTabs) > 0 then
        if currentTabMatches and currentTabPosition > 0 then
            -- Current tab matches, go to next one (wrap around)
            if currentTabPosition < (count of matchingTabs) then
                -- Go to next tab
                set nextTab to item (currentTabPosition + 1) of matchingTabs
            else
                -- Wrap around to first tab
                set nextTab to item 1 of matchingTabs
            end if
            set targetWindowIndex to windowIndex of nextTab
            set targetTabIndex to tabIndex of nextTab
            set foundTab to true
        else
            -- Current tab doesn't match, go to first matching tab
            set firstTab to item 1 of matchingTabs
            set targetWindowIndex to windowIndex of firstTab
            set targetTabIndex to tabIndex of firstTab
            set foundTab to true
        end if
    end if
    
    if foundTab then
        -- Found another matching tab, focus it
        activate
        set targetWindow to window targetWindowIndex
        set index of targetWindow to 1
        set active tab index of window 1 to targetTabIndex
    else if not anyMatchingTabFound then
        -- No matching tab found at all, create a new tab
        activate
        if (count of windows) is 0 then
            make new window
        end if
        set frontWindow to window 1
        set tabCount to count of tabs of frontWindow
        set newTab to make new tab at end of tabs of frontWindow with properties ${make_tab_url_prop}
        set active tab index of frontWindow to (tabCount + 1)
    else
        -- Current tab matches but no other matching tab found, just activate (stay on current)
        activate
    end if
end tell
APPLESCRIPT_EOF
else
    # Comet is not running, launch it and wait for tabs to restore, then search
    osascript <<${heredoc_delimiter}
tell application "Comet"
EOF
    
    # Add targetURL variable only if use_history is true
    if [ "$use_history" = "true" ]; then
        cat >> "${name}-focus.sh" <<EOF
    ${applescript_url_var}
EOF
    fi
    
    cat >> "${name}-focus.sh" <<EOF
    -- Launch Comet without opening a specific URL (so it restores previous tabs)
    activate
    
    -- Wait dynamically for Comet to fully launch and restore tabs
    -- Poll until windows exist and tabs are loaded (max 5 seconds)
    set maxWaitTime to 5
    set waitInterval to 0.1
    set waitedTime to 0
    set tabsReady to false
    
    repeat while waitedTime < maxWaitTime and not tabsReady
        try
            if (count of windows) > 0 then
                set firstWindow to window 1
                if (count of tabs of firstWindow) > 0 then
                    -- Check if tabs have URLs loaded (not just empty tabs)
                    try
                        set testTabURL to URL of tab 1 of firstWindow
                        if testTabURL is not "" then
                            set tabsReady to true
                        end if
                    end try
                end if
            end if
        end try
        
        if not tabsReady then
            delay waitInterval
            set waitedTime to waitedTime + waitInterval
        end if
    end repeat
    
    set targetWindowIndex to -1
    set targetTabIndex to -1
    set foundTab to false
    set currentTabURL to ""
    set currentWindowIndex to -1
    set currentTabIndex to -1
    set anyMatchingTabFound to false
    
    -- Get current active tab info first
    if (count of windows) > 0 then
        try
            set currentTabURL to URL of active tab of window 1
            set currentWindowIndex to 1
            set currentTabIndex to active tab index of window 1
        end try
    end if
    
    -- Check if current tab matches the URL pattern
    set currentTabMatches to false
    if currentTabURL is not "" then
        if ${current_url_condition} then
            set currentTabMatches to true
            set anyMatchingTabFound to true
        end if
    end if
    
    -- Collect all matching tabs in left-to-right order (window by window, tab by tab)
    set matchingTabs to {}
    set currentTabPosition to -1
    
    repeat with w from 1 to (count of windows)
        set windowTabs to tabs of window w
        repeat with t from 1 to (count of windowTabs)
            try
                set tabURL to URL of tab t of window w
                if ${tab_url_condition} then
                    set end of matchingTabs to {windowIndex:w, tabIndex:t}
                    set anyMatchingTabFound to true
                    -- Check if this is the current tab
                    if currentWindowIndex is w and currentTabIndex is t then
                        set currentTabPosition to (count of matchingTabs)
                    end if
                end if
            end try
        end repeat
    end repeat
    
    -- Determine which tab to switch to
    if (count of matchingTabs) > 0 then
        if currentTabMatches and currentTabPosition > 0 then
            -- Current tab matches, go to next one (wrap around)
            if currentTabPosition < (count of matchingTabs) then
                -- Go to next tab
                set nextTab to item (currentTabPosition + 1) of matchingTabs
            else
                -- Wrap around to first tab
                set nextTab to item 1 of matchingTabs
            end if
            set targetWindowIndex to windowIndex of nextTab
            set targetTabIndex to tabIndex of nextTab
            set foundTab to true
        else
            -- Current tab doesn't match, go to first matching tab
            set firstTab to item 1 of matchingTabs
            set targetWindowIndex to windowIndex of firstTab
            set targetTabIndex to tabIndex of firstTab
            set foundTab to true
        end if
    end if
    
    if foundTab then
        -- Found a matching tab, focus it
        set targetWindow to window targetWindowIndex
        set index of targetWindow to 1
        set active tab index of window 1 to targetTabIndex
    else if not anyMatchingTabFound then
        -- No matching tab found at all, create a new tab
        if (count of windows) is 0 then
            make new window
        end if
        set frontWindow to window 1
        set tabCount to count of tabs of frontWindow
        set newTab to make new tab at end of tabs of frontWindow with properties ${make_tab_url_prop}
        set active tab index of frontWindow to (tabCount + 1)
    else
        -- Current tab matches but no other matching tab found, just stay on current
    end if
end tell
APPLESCRIPT_EOF
fi
EOF
    
    chmod +x "${name}-focus.sh"
    echo "Generated ${name}-focus.sh (use_history: ${use_history})"
}

# Generate all scripts
for config in "${configs[@]}"; do
    IFS='|' read -r name title icon url_patterns default_url use_history <<< "$config"
    generate_script "$name" "$title" "$icon" "$url_patterns" "$default_url" "$use_history"
done

echo ""
echo "All focus scripts generated successfully!"


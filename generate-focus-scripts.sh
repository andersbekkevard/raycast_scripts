#!/bin/bash

# Metascript to generate focus scripts
# This script generates all focus scripts from a single template
#
# Usage: ./generate-focus-scripts.sh
#
# To add a new focus script:
# 1. Add a new entry to the configs array below
# 2. Format: "name|Title|icon|url_pattern1 url_pattern2|https://default-url.com"
# 3. Run this script to regenerate all focus scripts
#
# The generated scripts are identical in performance to manually written ones,
# as they use the same optimized search logic.

# Configuration: name|title|icon|url_patterns (space-separated)|default_url
configs=(
    "chatgpt|ChatGPT Focus|🤖|chat.openai.com chatgpt.com|https://chatgpt.com"
    "bb|Blackboard Focus|📚|blackboard.com ntnu.blackboard.com|https://ntnu.blackboard.com"
    "messenger|Messenger Focus|💬|messenger.com|https://messenger.com"
    "meet|Google Meet Focus|📹|meet.google.com|https://meet.google.com"
    "toggl|Toggl Focus|⏱️|track.toggl.com toggl.com|https://track.toggl.com/timer"
    "todoist|Todoist Focus|✅|app.todoist.com todoist.com|https://app.todoist.com/app/project/studie-6RWxW3r5GcXRrr8v"
    "youtube|YouTube Focus|📺|youtube.com www.youtube.com|https://www.youtube.com/"
    "calendar|Google Calendar Focus|📅|calendar.google.com|https://calendar.google.com/calendar/u/0/r"
    "gmail|Gmail Focus|📧|mail.google.com gmail.com|https://mail.google.com/mail/u/0/#inbox"
)

# Template for the AppleScript URL check condition
generate_url_condition() {
    local patterns="$1"
    local condition=""
    local first=true
    
    for pattern in $patterns; do
        if [ "$first" = true ]; then
            condition="activeTabURL contains \"$pattern\""
            first=false
        else
            condition="$condition or activeTabURL contains \"$pattern\""
        fi
    done
    
    echo "$condition"
}

# Generate a focus script
generate_script() {
    local name="$1"
    local title="$2"
    local icon="$3"
    local url_patterns="$4"
    local default_url="$5"
    
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

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, focus ${title} tab or open new tab
    osascript <<'APPLESCRIPT_EOF'
tell application "Comet"
    set targetWindowIndex to -1
    set targetTabIndex to -1
    set foundTab to false
    
    -- Optimized search: check frontmost window and active tab first (most common case)
    if (count of windows) > 0 then
        try
            set activeTabURL to URL of active tab of window 1
            if ${active_url_condition} then
                set targetWindowIndex to 1
                set targetTabIndex to active tab index of window 1
                set foundTab to true
            end if
        end try
        
        -- If not found in active tab, check other tabs in frontmost window
        if not foundTab then
            set windowTabs to tabs of window 1
            repeat with t from 1 to (count of windowTabs)
                try
                    set tabURL to URL of tab t of window 1
                    if ${tab_url_condition} then
                        set targetWindowIndex to 1
                        set targetTabIndex to t
                        set foundTab to true
                        exit repeat
                    end if
                end try
            end repeat
        end if
    end if
    
    -- If still not found, search other windows
    if not foundTab then
        repeat with w from 2 to (count of windows)
            set windowTabs to tabs of window w
            repeat with t from 1 to (count of windowTabs)
                try
                    set tabURL to URL of tab t of window w
                    if ${tab_url_condition} then
                        set targetWindowIndex to w
                        set targetTabIndex to t
                        set foundTab to true
                        exit repeat
                    end if
                end try
            end repeat
            if foundTab then exit repeat
        end repeat
    end if
    
    if foundTab then
        -- Tab exists, focus it
        -- First activate Comet, then bring the window containing the tab to front
        activate
        -- Store reference to the target window before changing its index
        set targetWindow to window targetWindowIndex
        -- Bring the window to front (this makes it window 1)
        set index of targetWindow to 1
        -- Now switch to the correct tab in the now-frontmost window
        set active tab index of window 1 to targetTabIndex
    else
        -- No tab found, create a new tab
        activate
        if (count of windows) is 0 then
            make new window
        end if
        set frontWindow to window 1
        set tabCount to count of tabs of frontWindow
        set newTab to make new tab at end of tabs of frontWindow with properties {URL:"${default_url}"}
        set active tab index of frontWindow to (tabCount + 1)
    end if
end tell
APPLESCRIPT_EOF
else
    # Comet is not running, launch it normally (not as app)
    open -a Comet "${default_url}"
fi
EOF
    
    chmod +x "${name}-focus.sh"
    echo "Generated ${name}-focus.sh"
}

# Generate all scripts
for config in "${configs[@]}"; do
    IFS='|' read -r name title icon url_patterns default_url <<< "$config"
    generate_script "$name" "$title" "$icon" "$url_patterns" "$default_url"
done

echo ""
echo "All focus scripts generated successfully!"


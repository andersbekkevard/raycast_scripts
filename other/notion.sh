#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Notion Toggle
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, toggle Notion window
    osascript <<'EOF'
tell application "System Events"
    set cometIsFrontmost to (name of first application process whose frontmost is true) is "Comet"
end tell

tell application "Comet"
    set notionWindow to missing value
    set notionIndex to -1
    set windowCount to count of windows
    
    -- Find the Notion window by checking the active tab's URL
    -- This works even when the window title changes
    repeat with i from 1 to windowCount
        set w to window i
        set isNotionWindow to false
        
        -- Check the active tab's URL (most reliable method)
        try
            set tabURL to URL of active tab of w
            if tabURL contains "notion.so" then
                set isNotionWindow to true
            end if
        end try
        
        -- Fallback: Check window title for Notion indicators (for initial load)
        if not isNotionWindow then
            set windowTitle to name of w
            if windowTitle contains "Notion" or windowTitle contains "notion" or windowTitle contains "notion.so" then
                set isNotionWindow to true
            end if
        end if
        
        if isNotionWindow then
            set notionWindow to w
            set notionIndex to i
            exit repeat
        end if
    end repeat
    
    if notionIndex is -1 then
        -- No Notion window found, create one
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://notion.so' &> /dev/null &"
    else if cometIsFrontmost and notionIndex is 1 then
        -- Notion is in focus, toggle it off
        if windowCount > 1 then
            -- Multiple windows: bring next window to front
            set nextWindowIndex to notionIndex + 1
            if nextWindowIndex > windowCount then
                set nextWindowIndex to 1
            end if
            
            if nextWindowIndex is not notionIndex then
                set index of window nextWindowIndex to 1
            end if
        else
            -- Only Notion window: hide the app
            tell application "System Events"
                set visible of process "Comet" to false
            end tell
        end if
    else
        -- Notion exists but not in focus, bring it to front
        activate
        set index of notionWindow to 1
    end if
end tell
EOF
else
    # Comet is not running, launch it
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://notion.so" &
fi


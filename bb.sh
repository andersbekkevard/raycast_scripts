#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Blackboard Toggle
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📚

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, toggle Blackboard window
    osascript <<'EOF'
tell application "System Events"
    set cometIsFrontmost to (name of first application process whose frontmost is true) is "Comet"
end tell

tell application "Comet"
    set blackboardWindow to missing value
    set blackboardIndex to -1
    set windowCount to count of windows
    
    -- Find the Blackboard window by checking the active tab's URL
    -- This works even when the window title changes
    repeat with i from 1 to windowCount
        set w to window i
        set isBlackboardWindow to false
        
        -- Check the active tab's URL (most reliable method)
        try
            set tabURL to URL of active tab of w
            if tabURL contains "blackboard.com" or tabURL contains "ntnu.blackboard.com" then
                set isBlackboardWindow to true
            end if
        end try
        
        -- Fallback: Check window title for Blackboard indicators (for initial load)
        if not isBlackboardWindow then
            set windowTitle to name of w
            if windowTitle contains "Blackboard" or windowTitle contains "blackboard" or windowTitle contains "blackboard.com" then
                set isBlackboardWindow to true
            end if
        end if
        
        if isBlackboardWindow then
            set blackboardWindow to w
            set blackboardIndex to i
            exit repeat
        end if
    end repeat
    
    if blackboardIndex is -1 then
        -- No Blackboard window found, create one
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://ntnu.blackboard.com' &> /dev/null &"
    else if cometIsFrontmost and blackboardIndex is 1 then
        -- Blackboard is in focus, toggle it off
        if windowCount > 1 then
            -- Multiple windows: bring next window to front
            set nextWindowIndex to blackboardIndex + 1
            if nextWindowIndex > windowCount then
                set nextWindowIndex to 1
            end if
            
            if nextWindowIndex is not blackboardIndex then
                set index of window nextWindowIndex to 1
            end if
        else
            -- Only Blackboard window: hide the app
            tell application "System Events"
                set visible of process "Comet" to false
            end tell
        end if
    else
        -- Blackboard exists but not in focus, bring it to front
        activate
        set index of blackboardWindow to 1
    end if
end tell
EOF
else
    # Comet is not running, launch it
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://ntnu.blackboard.com" &
fi


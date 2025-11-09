#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Google Meet Toggle
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📹

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, toggle Google Meet window
    osascript <<'EOF'
tell application "System Events"
    set cometIsFrontmost to (name of first application process whose frontmost is true) is "Comet"
end tell

tell application "Comet"
    set meetWindow to missing value
    set meetIndex to -1
    set windowCount to count of windows
    
    -- Find the Google Meet window by checking the active tab's URL
    -- This works even when the window title changes
    repeat with i from 1 to windowCount
        set w to window i
        set isMeetWindow to false
        
        -- Check the active tab's URL (most reliable method)
        try
            set tabURL to URL of active tab of w
            if tabURL contains "meet.google.com" then
                set isMeetWindow to true
            end if
        end try
        
        -- Fallback: Check window title for Google Meet indicators (for initial load)
        if not isMeetWindow then
            set windowTitle to name of w
            if windowTitle contains "Google Meet" or windowTitle contains "meet.google.com" or windowTitle contains "Meet" then
                set isMeetWindow to true
            end if
        end if
        
        if isMeetWindow then
            set meetWindow to w
            set meetIndex to i
            exit repeat
        end if
    end repeat
    
    if meetIndex is -1 then
        -- No Google Meet window found, create one
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://meet.google.com' &> /dev/null &"
    else if cometIsFrontmost and meetIndex is 1 then
        -- Google Meet is in focus, toggle it off
        if windowCount > 1 then
            -- Multiple windows: bring next window to front
            set nextWindowIndex to meetIndex + 1
            if nextWindowIndex > windowCount then
                set nextWindowIndex to 1
            end if
            
            if nextWindowIndex is not meetIndex then
                set index of window nextWindowIndex to 1
            end if
        else
            -- Only Google Meet window: hide the app
            tell application "System Events"
                set visible of process "Comet" to false
            end tell
        end if
    else
        -- Google Meet exists but not in focus, bring it to front
        activate
        set index of meetWindow to 1
    end if
end tell
EOF
else
    # Comet is not running, launch it
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://meet.google.com" &
fi


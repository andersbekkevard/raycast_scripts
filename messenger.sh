#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Messenger Toggle
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💬

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, toggle Messenger window
    osascript <<'EOF'
tell application "System Events"
    set cometIsFrontmost to (name of first application process whose frontmost is true) is "Comet"
end tell

tell application "Comet"
    set messengerWindow to missing value
    set messengerIndex to -1
    set windowCount to count of windows
    
    -- Find the Messenger window
    repeat with i from 1 to windowCount
        set w to window i
        set windowTitle to name of w
        if windowTitle contains "Messenger" or windowTitle contains "messenger" or windowTitle contains "messenger.com" then
            set messengerWindow to w
            set messengerIndex to i
            exit repeat
        end if
    end repeat
    
    if messengerIndex is -1 then
        -- No Messenger window found, create one
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://messenger.com' &> /dev/null &"
    else if cometIsFrontmost and messengerIndex is 1 then
        -- Messenger is in focus, toggle it off
        if windowCount > 1 then
            -- Multiple windows: bring next window to front
            set nextWindowIndex to messengerIndex + 1
            if nextWindowIndex > windowCount then
                set nextWindowIndex to 1
            end if
            
            if nextWindowIndex is not messengerIndex then
                set index of window nextWindowIndex to 1
            end if
        else
            -- Only Messenger window: hide the app
            tell application "System Events"
                set visible of process "Comet" to false
            end tell
        end if
    else
        -- Messenger exists but not in focus, bring it to front
        activate
        set index of messengerWindow to 1
    end if
end tell
EOF
else
    # Comet is not running, launch it
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://messenger.com" &
fi


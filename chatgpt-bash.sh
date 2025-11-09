#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ChatGPT Open (Bash)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running with a ChatGPT window
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, check if ChatGPT window is in focus and toggle
    osascript <<EOF
tell application "Comet"
    set windowFound to false
    set chatgptWindow to missing value
    
    -- Find the ChatGPT window
    repeat with w in windows
        if (name of w contains "ChatGPT" or name of w contains "chatgpt") then
            set chatgptWindow to w
            set windowFound to true
            exit repeat
        end if
    end repeat
    
    if windowFound then
        -- Check if ChatGPT window is already frontmost
        if index of chatgptWindow is 1 and frontmost is true then
            -- It's in focus, so hide the application using Cmd+H
            tell application "System Events"
                keystroke "h" using command down
            end tell
        else
            -- It's not in focus, bring it to front
            activate
            set index of chatgptWindow to 1
        end if
    else
        -- No ChatGPT window found, create one
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' &> /dev/null &"
    end if
end tell
EOF
else
    # Comet is not running, launch it with the app
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://chatgpt.com" &
fi
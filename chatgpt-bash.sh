#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ChatGPT Toggle (Bash)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, toggle ChatGPT window
    osascript <<'EOF'
tell application "System Events"
    set cometIsFrontmost to (name of first application process whose frontmost is true) is "Comet"
end tell

tell application "Comet"
    set chatgptWindow to missing value
    set chatgptIndex to -1
    set windowCount to count of windows
    
    -- Find the ChatGPT window by checking the active tab's URL
    -- This works even when the window title changes to the conversation name
    repeat with i from 1 to windowCount
        set w to window i
        set isChatGPTWindow to false
        
        -- Check the active tab's URL (most reliable method)
        try
            set tabURL to URL of active tab of w
            if tabURL contains "chat.openai.com" or tabURL contains "chatgpt.com" then
                set isChatGPTWindow to true
            end if
        end try
        
        -- Fallback: Check window title for ChatGPT indicators (for initial load)
        if not isChatGPTWindow then
            set windowTitle to name of w
            if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" or windowTitle contains "chatgpt.com" then
                set isChatGPTWindow to true
            end if
        end if
        
        if isChatGPTWindow then
            set chatgptWindow to w
            set chatgptIndex to i
            exit repeat
        end if
    end repeat
    
    if chatgptIndex is -1 then
        -- No ChatGPT window found, create one
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' &> /dev/null &"
    else if cometIsFrontmost and chatgptIndex is 1 then
        -- ChatGPT is in focus, toggle it off
        if windowCount > 1 then
            -- Multiple windows: bring next window to front
            set nextWindowIndex to chatgptIndex + 1
            if nextWindowIndex > windowCount then
                set nextWindowIndex to 1
            end if
            
            if nextWindowIndex is not chatgptIndex then
                set index of window nextWindowIndex to 1
            end if
        else
            -- Only ChatGPT window: hide the app
            tell application "System Events"
                set visible of process "Comet" to false
            end tell
        end if
    else
        -- ChatGPT exists but not in focus, bring it to front
        activate
        set index of chatgptWindow to 1
    end if
end tell
EOF
else
    # Comet is not running, launch it
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://chatgpt.com" &
fi
#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Gemini Toggle 
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, toggle Gemini window
    osascript <<'EOF'
tell application "System Events"
    set cometIsFrontmost to (name of first application process whose frontmost is true) is "Comet"
end tell

tell application "Comet"
    set geminiWindow to missing value
    set geminiIndex to -1
    set windowCount to count of windows
    
    -- Find the Gemini window by checking the active tab's URL
    -- This works even when the window title changes
    repeat with i from 1 to windowCount
        set w to window i
        set isGeminiWindow to false
        
        -- Check the active tab's URL (most reliable method)
        try
            set tabURL to URL of active tab of w
            if tabURL contains "gemini.google.com" then
                set isGeminiWindow to true
            end if
        end try
        
        -- Fallback: Check window title for Gemini indicators (for initial load)
        if not isGeminiWindow then
            set windowTitle to name of w
            if windowTitle contains "Gemini" or windowTitle contains "gemini.google.com" then
                set isGeminiWindow to true
            end if
        end if
        
        if isGeminiWindow then
            set geminiWindow to w
            set geminiIndex to i
            exit repeat
        end if
    end repeat
    
    if geminiIndex is -1 then
        -- No Gemini window found, create one
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://gemini.google.com/' &> /dev/null &"
    else if cometIsFrontmost and geminiIndex is 1 then
        -- Gemini is in focus, toggle it off
        if windowCount > 1 then
            -- Multiple windows: bring next window to front
            set nextWindowIndex to geminiIndex + 1
            if nextWindowIndex > windowCount then
                set nextWindowIndex to 1
            end if
            
            if nextWindowIndex is not geminiIndex then
                set index of window nextWindowIndex to 1
            end if
        else
            -- Only Gemini window: hide the app
            tell application "System Events"
                set visible of process "Comet" to false
            end tell
        end if
    else
        -- Gemini exists but not in focus, bring it to front
        activate
        set index of geminiWindow to 1
    end if
end tell
EOF
else
    # Comet is not running, launch it
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://gemini.google.com/" &
fi
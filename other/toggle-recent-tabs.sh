#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Recent Tabs
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔄

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Toggle between the two most recently used browser tabs

# State file to store previous tab info
STATE_FILE="$HOME/.cache/raycast-tab-toggle-state.json"

# Ensure the directory exists
mkdir -p "$(dirname "$STATE_FILE")"

# Check if Comet is running
if ! pgrep -x "Comet" > /dev/null; then
    exit 1
fi

# AppleScript to toggle between tabs
osascript <<APPLESCRIPT_EOF
tell application "Comet"
    -- Ensure we have windows
    if (count of windows) is 0 then
        return
    end if
    
    set stateFile to "$STATE_FILE"
    
    -- Get current active tab info
    set currentWindow to 1
    set currentTab to active tab index of window 1
    set currentURL to URL of active tab of window 1
    
    -- Read previous state from file
    set previousWindow to -1
    set previousTab to -1
    set previousURL to ""
    
    try
        set stateContent to do shell script "cat " & quoted form of stateFile
        
        -- Parse JSON manually (simple parsing since we control the format)
        set AppleScript's text item delimiters to "\\"window\\":"
        set temp to text item 2 of stateContent
        set AppleScript's text item delimiters to ","
        set previousWindow to (text item 1 of temp) as integer
        
        set AppleScript's text item delimiters to "\\"tab\\":"
        set temp to text item 2 of stateContent
        set AppleScript's text item delimiters to ","
        set previousTab to (text item 1 of temp) as integer
        
        set AppleScript's text item delimiters to "\\"url\\":\\""
        set temp to text item 2 of stateContent
        set AppleScript's text item delimiters to "\\""
        set previousURL to text item 1 of temp
        
        set AppleScript's text item delimiters to ""
    on error
        -- No previous state or parsing error
        set previousWindow to -1
        set previousTab to -1
    end try
    
    -- Check if we have valid previous state and it's different from current
    set shouldToggle to false
    if previousWindow is not -1 and previousTab is not -1 then
        -- Check if previous tab still exists and is different from current
        try
            if previousWindow ≤ (count of windows) then
                if previousTab ≤ (count of tabs of window previousWindow) then
                    -- Previous tab exists
                    if not (previousWindow is currentWindow and previousTab is currentTab) then
                        set shouldToggle to true
                    end if
                end if
            end if
        end try
    end if
    
    if shouldToggle then
        -- Switch to previous tab
        set targetWindow to window previousWindow
        set index of targetWindow to 1
        set active tab index of window 1 to previousTab
        
        -- Save the OLD current tab (the one we were just on) as the new "previous" state
        set stateJSON to "{\\"window\\":" & currentWindow & ",\\"tab\\":" & currentTab & ",\\"url\\":\\"" & currentURL & "\\"}"
        do shell script "echo " & quoted form of stateJSON & " > " & quoted form of stateFile
    else
        -- No valid previous state or same tab, just save current state
        set stateJSON to "{\\"window\\":" & currentWindow & ",\\"tab\\":" & currentTab & ",\\"url\\":\\"" & currentURL & "\\"}"
        do shell script "echo " & quoted form of stateJSON & " > " & quoted form of stateFile
    end if
end tell
APPLESCRIPT_EOF


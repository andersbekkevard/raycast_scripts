#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Google Meet Focus
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📹

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, focus Google Meet Focus tab or open new tab
    osascript <<'APPLESCRIPT_EOF'
tell application "Comet"
    set targetWindowIndex to -1
    set targetTabIndex to -1
    set foundTab to false
    
    -- Optimized search: check frontmost window and active tab first (most common case)
    if (count of windows) > 0 then
        try
            set activeTabURL to URL of active tab of window 1
            if activeTabURL contains "meet.google.com" then
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
                    if tabURL contains "meet.google.com" then
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
                    if tabURL contains "meet.google.com" then
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
        set newTab to make new tab at end of tabs of frontWindow with properties {URL:"https://meet.google.com"}
        set active tab index of frontWindow to (tabCount + 1)
    end if
end tell
APPLESCRIPT_EOF
else
    # Comet is not running, launch it normally (not as app)
    open -a Comet "https://meet.google.com"
fi

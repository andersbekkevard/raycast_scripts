#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Panopto Focus
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎥

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, find nearest Panopto tab (skip current if it's Panopto)
    osascript <<'APPLESCRIPT_EOF'
tell application "Comet"
    set targetWindowIndex to -1
    set targetTabIndex to -1
    set foundTab to false
    set currentTabURL to ""
    set currentWindowIndex to -1
    set currentTabIndex to -1
    
    -- Get current active tab info first
    if (count of windows) > 0 then
        try
            set currentTabURL to URL of active tab of window 1
            set currentWindowIndex to 1
            set currentTabIndex to active tab index of window 1
        end try
    end if
    
    -- Check if current tab is Panopto
    set currentTabIsPanopto to (currentTabURL contains "panopto.eu")
    
    -- Search strategy: if current tab is Panopto, start searching from next tab
    -- Otherwise, start from current tab
    
    -- First, search in frontmost window
    if (count of windows) > 0 then
        set windowTabs to tabs of window 1
        set startTab to 1
        
        -- If current tab is Panopto, start from next tab
        if currentTabIsPanopto and currentWindowIndex is 1 then
            set startTab to currentTabIndex + 1
        end if
        
        -- Search tabs in frontmost window starting from startTab
        repeat with t from startTab to (count of windowTabs)
            try
                set tabURL to URL of tab t of window 1
                if tabURL contains "panopto.eu" then
                    -- Skip if this is the current tab
                    if not (currentWindowIndex is 1 and currentTabIndex is t) then
                        set targetWindowIndex to 1
                        set targetTabIndex to t
                        set foundTab to true
                        exit repeat
                    end if
                end if
            end try
        end repeat
        
        -- If not found and current tab is Panopto, also check tabs before current tab
        if not foundTab and currentTabIsPanopto and currentWindowIndex is 1 then
            repeat with t from 1 to (currentTabIndex - 1)
                try
                    set tabURL to URL of tab t of window 1
                    if tabURL contains "panopto.eu" then
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
                    if tabURL contains "panopto.eu" then
                        -- Skip if this is the current tab
                        if not (currentWindowIndex is w and currentTabIndex is t) then
                            set targetWindowIndex to w
                            set targetTabIndex to t
                            set foundTab to true
                            exit repeat
                        end if
                    end if
                end try
            end repeat
            if foundTab then exit repeat
        end repeat
    end if
    
    -- If current tab is Panopto but no other Panopto tab found, also check window 1 tabs before current
    -- (This handles the case where we started searching from a later tab)
    if not foundTab and currentTabIsPanopto and currentWindowIndex is 1 and (count of windows) > 0 then
        set windowTabs to tabs of window 1
        repeat with t from 1 to (currentTabIndex - 1)
            try
                set tabURL to URL of tab t of window 1
                if tabURL contains "panopto.eu" then
                    set targetWindowIndex to 1
                    set targetTabIndex to t
                    set foundTab to true
                    exit repeat
                end if
            end try
        end repeat
    end if
    
    if foundTab then
        -- Found another Panopto tab, focus it
        activate
        set targetWindow to window targetWindowIndex
        set index of targetWindow to 1
        set active tab index of window 1 to targetTabIndex
    else
        -- No other Panopto tab found, just activate Comet (don't open new tab)
        activate
    end if
end tell
APPLESCRIPT_EOF
else
    # Comet is not running, do nothing (don't open new tab)
    exit 0
fi


#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Gmail Focus
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📧

# Documentation:
# @raycast.author Anders Bekkevard

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Comet is running, focus Gmail Focus tab or open new tab
    osascript <<'APPLESCRIPT_EOF'
tell application "Comet"
    set targetWindowIndex to -1
    set targetTabIndex to -1
    set foundTab to false
    set currentTabURL to ""
    set currentWindowIndex to -1
    set currentTabIndex to -1
    set anyMatchingTabFound to false
    
    -- Get current active tab info first
    if (count of windows) > 0 then
        try
            set currentTabURL to URL of active tab of window 1
            set currentWindowIndex to 1
            set currentTabIndex to active tab index of window 1
        end try
    end if
    
    -- Check if current tab matches the URL pattern
    set currentTabMatches to false
    if currentTabURL is not "" then
        if currentTabURL contains "mail.google.com" or currentTabURL contains "gmail.com" then
            set currentTabMatches to true
            set anyMatchingTabFound to true
        end if
    end if
    
    -- Collect all matching tabs in left-to-right order (window by window, tab by tab)
    set matchingTabs to {}
    set currentTabPosition to -1
    
    repeat with w from 1 to (count of windows)
        set windowTabs to tabs of window w
        repeat with t from 1 to (count of windowTabs)
            try
                set tabURL to URL of tab t of window w
                if tabURL contains "mail.google.com" or tabURL contains "gmail.com" then
                    set end of matchingTabs to {windowIndex:w, tabIndex:t}
                    set anyMatchingTabFound to true
                    -- Check if this is the current tab
                    if currentWindowIndex is w and currentTabIndex is t then
                        set currentTabPosition to (count of matchingTabs)
                    end if
                end if
            end try
        end repeat
    end repeat
    
    -- Determine which tab to switch to
    if (count of matchingTabs) > 0 then
        if currentTabMatches and currentTabPosition > 0 then
            -- Current tab matches, go to next one (wrap around)
            if currentTabPosition < (count of matchingTabs) then
                -- Go to next tab
                set nextTab to item (currentTabPosition + 1) of matchingTabs
            else
                -- Wrap around to first tab
                set nextTab to item 1 of matchingTabs
            end if
            set targetWindowIndex to windowIndex of nextTab
            set targetTabIndex to tabIndex of nextTab
            set foundTab to true
        else
            -- Current tab doesn't match, go to first matching tab
            set firstTab to item 1 of matchingTabs
            set targetWindowIndex to windowIndex of firstTab
            set targetTabIndex to tabIndex of firstTab
            set foundTab to true
        end if
    end if
    
    if foundTab then
        -- Found another matching tab, focus it
        activate
        set targetWindow to window targetWindowIndex
        set index of targetWindow to 1
        set active tab index of window 1 to targetTabIndex
    else if not anyMatchingTabFound then
        -- No matching tab found at all, create a new tab
        activate
        if (count of windows) is 0 then
            make new window
        end if
        set frontWindow to window 1
        set tabCount to count of tabs of frontWindow
        set newTab to make new tab at end of tabs of frontWindow with properties {URL:"https://mail.google.com/mail/u/0/#inbox"}
        set active tab index of frontWindow to (tabCount + 1)
    else
        -- Current tab matches but no other matching tab found, just activate (stay on current)
        activate
    end if
end tell
APPLESCRIPT_EOF
else
    # Comet is not running, launch it normally (not as app)
    open -a Comet "https://mail.google.com/mail/u/0/#inbox"
fi

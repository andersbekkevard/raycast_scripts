#!/bin/bash

# Helper script to list all Notes folders
# Run this to see what folder names are available

osascript <<'APPLESCRIPT_EOF'
tell application "Notes"
    set folderList to {}
    repeat with aFolder in folders
        set end of folderList to name of aFolder
    end repeat
    
    set AppleScript's text item delimiters to return
    set folderNames to folderList as string
    set AppleScript's text item delimiters to ""
    
    display dialog "Available Notes folders:" & return & return & folderNames buttons {"OK"} default button "OK"
end tell
APPLESCRIPT_EOF


#!/bin/bash

# Test script to debug note searching
NOTE_NAME="Scribbledown"
NOTE_FOLDER="Notes"

osascript <<APPLESCRIPT_EOF
tell application "Notes"
    try
        -- Find the folder
        set targetFolder to missing value
        if "${NOTE_FOLDER}" is not "" then
            repeat with aFolder in folders
                if name of aFolder is "${NOTE_FOLDER}" then
                    set targetFolder to aFolder
                    exit repeat
                end if
            end repeat
        end if
        
        if targetFolder is missing value then
            display dialog "Folder '${NOTE_FOLDER}' not found!" buttons {"OK"}
            return
        end if
        
        -- Try direct lookup
        set foundNote to missing value
        try
            set foundNote to note "${NOTE_NAME}" of targetFolder
            display dialog "Found note using direct lookup: " & name of foundNote buttons {"OK"}
        on error errMsg
            display dialog "Direct lookup failed: " & errMsg buttons {"OK"}
            
            -- Try listing all notes
            try
                set folderNotes to every note of targetFolder
                set noteNames to {}
                repeat with aNote in folderNotes
                    try
                        set end of noteNames to name of aNote
                    end try
                end repeat
                
                set AppleScript's text item delimiters to return
                set namesList to noteNames as string
                set AppleScript's text item delimiters to ""
                
                display dialog "Notes in folder:" & return & return & namesList buttons {"OK"}
            on error listErr
                display dialog "Could not list notes: " & listErr buttons {"OK"}
            end try
        end try
    on error mainErr
        display dialog "Error: " & mainErr buttons {"OK"}
    end try
end tell
APPLESCRIPT_EOF


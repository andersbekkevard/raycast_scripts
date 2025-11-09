#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Scribbledown to Note
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Saves clipboard content to Apple Note

# Configuration - Change these to your desired note name and folder
NOTE_FOLDER="Scribbledown"  # Apple Notes folder name
NOTE_NAME="Scribbledown"    # Name of the note in that folder (will use first note if exists, or create this name)

# Rate limiting
LOCK_DIR="/tmp/scribbledown_lock"
TIMESTAMP_FILE="/tmp/scribbledown.timestamp"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi

# Cleanup function
cleanup() {
    rm -rf "$LOCK_DIR"
    [ -n "$TEXT_TEMP_FILE" ] && rm -f "$TEXT_TEMP_FILE"
}

trap cleanup EXIT

CURRENT_TIMESTAMP=$(date +%s)
if [ -f "$TIMESTAMP_FILE" ]; then
    LAST_TIMESTAMP=$(cat "$TIMESTAMP_FILE")
    TIME_DIFF=$((CURRENT_TIMESTAMP - LAST_TIMESTAMP))
    if [ "$TIME_DIFF" -lt 1 ]; then
        exit 0
    fi
fi

echo "$CURRENT_TIMESTAMP" > "$TIMESTAMP_FILE"

# Get clipboard content
TEXT_CONTENT=$(osascript 2>/dev/null <<'APPLESCRIPT_END'
try
    set clipInfo to (clipboard info) as string
    
    -- Check for binary/image data
    if clipInfo contains "PNGf" or clipInfo contains "TIFF" or clipInfo contains "JPEG" or clipInfo contains "GIFf" then
        return "BINARY_DATA"
    end if
    if clipInfo contains "public.png" or clipInfo contains "public.tiff" or clipInfo contains "public.jpeg" then
        return "BINARY_DATA"
    end if
    if clipInfo contains "furl" or clipInfo contains "public.file-url" then
        return "BINARY_DATA"
    end if
    
    -- Get clipboard as text
    set clipText to the clipboard as text
    
    if clipText is "" or clipText is missing value then
        return "NO_TEXT"
    end if
    
    -- Check if suspiciously long (might be binary coerced to text)
    set textLen to length of clipText
    if textLen > 10000 then
        set sample to text 1 thru 500 of clipText
        if sample contains "data" or sample contains "class" then
            return "BINARY_DATA"
        end if
    end if
    
    return clipText
on error errMsg
    return "ERROR:" & errMsg
end try
APPLESCRIPT_END
)

# Check result
if [[ "$TEXT_CONTENT" == "BINARY_DATA" ]] || [[ "$TEXT_CONTENT" == "NO_TEXT" ]] || [[ -z "$TEXT_CONTENT" ]]; then
    exit 0
fi

if [[ "$TEXT_CONTENT" == ERROR:* ]]; then
    exit 0
fi

# Don't save if content is only whitespace
if [[ -z "${TEXT_CONTENT// }" ]]; then
    exit 0
fi

# Additional binary checks
if echo "$TEXT_CONTENT" | grep -q "class"; then
    exit 0
fi

if echo "$TEXT_CONTENT" | grep -q "data"; then
    exit 0
fi

TEXT_LENGTH=${#TEXT_CONTENT}
if [ "$TEXT_LENGTH" -gt 5000 ]; then
    SAMPLE="${TEXT_CONTENT:0:1000}"
    HEX_COUNT=$(echo "$SAMPLE" | grep -o "[0-9A-Fa-f]" | wc -l | tr -d ' ')
    TOTAL_COUNT=$(echo "$SAMPLE" | wc -c | tr -d ' ')
    if [ "$HEX_COUNT" -gt $((TOTAL_COUNT * 80 / 100)) ]; then
        exit 0
    fi
fi

# Prepare content to append
CURRENT_DATE=$(date +"%Y-%m-%d")
CURRENT_TIME=$(date +"%H:%M:%S")
TIMESTAMP="$CURRENT_DATE $CURRENT_TIME"

# Write text content to temp file for safe passing to AppleScript
TEXT_TEMP_FILE=$(mktemp)
echo -n "$TEXT_CONTENT" > "$TEXT_TEMP_FILE"

# Append to Apple Note using AppleScript
osascript <<APPLESCRIPT_EOF
tell application "Notes"
    try
        -- Read text content from temp file
        set textFile to POSIX file "${TEXT_TEMP_FILE}"
        set newTextContent to (read textFile as «class utf8»)
        
        -- Determine target folder
        set targetFolder to missing value
        if "${NOTE_FOLDER}" is not "" then
            -- Try to find folder by name (search through all folders)
            repeat with aFolder in folders
                if name of aFolder is "${NOTE_FOLDER}" then
                    set targetFolder to aFolder
                    exit repeat
                end if
            end repeat
            
            -- If folder not found by name, use default folder
            if targetFolder is missing value then
                set targetFolder to folder 1
            end if
        else
            -- Use default folder (first folder)
            set targetFolder to folder 1
        end if
        
        -- Try to find the note in the target folder
        set targetNote to missing value
        
        -- Get all notes in the folder
        try
            set folderNotes to every note of targetFolder
            set noteCount to count of folderNotes
            
            if noteCount > 0 then
                -- Use the first note in the folder
                set targetNote to item 1 of folderNotes
            end if
        on error
            -- Couldn't access notes, try direct lookup
            try
                set targetNote to note "${NOTE_NAME}" of targetFolder
            on error
                -- Note doesn't exist
            end try
        end try
        
        -- If no note exists, create one in the target folder
        if targetNote is missing value then
            set targetNote to make new note at targetFolder with properties {name:"${NOTE_NAME}", body:""}
        end if
        
        -- Get current note body
        set currentBody to body of targetNote
        
        -- Check for duplicate (simple check against last entry)
        set isDuplicate to false
        if currentBody is not "" then
            try
                set AppleScript's text item delimiters to return
                set bodyLines to text items of currentBody
                set AppleScript's text item delimiters to ""
                
                -- Check first few lines for duplicate
                if (count of bodyLines) > 1 then
                    set firstLine to item 1 of bodyLines
                    set secondLine to item 2 of bodyLines
                    -- If first line is title, check second entry
                    if firstLine does not contain "[" then
                        if (count of bodyLines) > 2 then
                            set secondLine to item 3 of bodyLines
                        end if
                    end if
                    -- Check if content matches
                    if secondLine is newTextContent then
                        if firstLine contains "[" and firstLine contains "]" then
                            set AppleScript's text item delimiters to "]"
                            set datePart to text item 1 of firstLine
                            set AppleScript's text item delimiters to "["
                            set datePart to text item 2 of datePart
                            set AppleScript's text item delimiters to ""
                            if datePart contains "${CURRENT_DATE}" then
                                set timePart to text 12 thru 16 of datePart
                                set currentTimeShort to text 1 thru 5 of "${CURRENT_TIME}"
                                if timePart is currentTimeShort then
                                    set isDuplicate to true
                                end if
                            end if
                        end if
                    end if
                end if
            end try
        end if
        
        if isDuplicate then
            return
        end if
        
        -- Check if we need a day separator
        set needsDaySeparator to false
        if currentBody is "" then
            set needsDaySeparator to true
        else
            try
                set AppleScript's text item delimiters to return
                set bodyLines to text items of currentBody
                set AppleScript's text item delimiters to ""
                -- Find first timestamp entry
                repeat with aLine in bodyLines
                    if aLine contains "[" and aLine contains "]" then
                        set AppleScript's text item delimiters to "]"
                        set datePart to text item 1 of aLine
                        set AppleScript's text item delimiters to "["
                        set datePart to text item 2 of datePart
                        set AppleScript's text item delimiters to ""
                        set lastDate to text 1 thru 10 of datePart
                        if lastDate is not "${CURRENT_DATE}" then
                            set needsDaySeparator to true
                        end if
                        exit repeat
                    end if
                end repeat
            end try
        end if
        
        -- Build new content
        set newContent to "[${TIMESTAMP}]" & return & newTextContent & return & return
        
        if needsDaySeparator then
            set daySeparator to return & return & "═══════════════════════════════════════" & return & "  ${CURRENT_DATE}" & return & "═══════════════════════════════════════" & return & return
            set newContent to daySeparator & newContent
        end if
        
        -- Check if note has title (first line is title, not timestamp)
        set hasTitle to false
        set noteTitle to ""
        if currentBody is not "" then
            try
                set AppleScript's text item delimiters to return
                set bodyLines to text items of currentBody
                set AppleScript's text item delimiters to ""
                if (count of bodyLines) > 0 then
                    set firstLine to item 1 of bodyLines
                    if firstLine does not contain "[" and (firstLine is "${NOTE_NAME}" or firstLine contains "${NOTE_NAME}") then
                        set hasTitle to true
                        set noteTitle to firstLine & return & return
                    end if
                end if
            end try
        end if
        
        -- Prepend new content
        if hasTitle then
            -- Keep title, prepend new content after it
            set body of targetNote to noteTitle & newContent & currentBody
        else if currentBody is "" then
            -- Empty note, add title and content
            set body of targetNote to "${NOTE_NAME}" & return & return & newContent
        else
            -- No title, just prepend
            set body of targetNote to newContent & currentBody
        end if
        
        -- Show notification
        display notification "Saved to ${NOTE_NAME}!" with title "Scribbledown" sound name "Glass"
    on error errMsg
        -- Silently fail if there's an error
        return
    end try
end tell
APPLESCRIPT_EOF


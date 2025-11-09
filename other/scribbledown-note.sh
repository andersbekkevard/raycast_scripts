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
        
        -- Get current note body (as raw text to preserve formatting)
        set currentBody to body of targetNote as string
        
        -- Extract title if it exists (first line if it's "Scribbledown" or similar)
        set noteTitle to ""
        set contentWithoutTitle to currentBody
        set lineBreak to return
        
        -- Check if body starts with title
        if currentBody is not "" then
            set AppleScript's text item delimiters to lineBreak
            set bodyLines to text items of currentBody
            set AppleScript's text item delimiters to ""
            
            if (count of bodyLines) > 0 then
                set firstLine to item 1 of bodyLines
                -- Check if first line is a title (not a timestamp entry)
                if firstLine does not contain "[" or firstLine does not contain "]" then
                    -- First line might be a title, check if it's "Scribbledown" or similar
                    if firstLine is "${NOTE_NAME}" or firstLine contains "${NOTE_NAME}" then
                        set noteTitle to firstLine & lineBreak & lineBreak
                        -- Get content after title (preserve all formatting including multiple newlines)
                        if (count of bodyLines) > 1 then
                            -- Rebuild content starting from line 2, preserving original line breaks
                            set contentWithoutTitle to ""
                            repeat with i from 2 to (count of bodyLines)
                                if i is 2 then
                                    set contentWithoutTitle to item i of bodyLines
                                else
                                    set contentWithoutTitle to contentWithoutTitle & lineBreak & item i of bodyLines
                                end if
                            end repeat
                        else
                            set contentWithoutTitle to ""
                        end if
                    end if
                end if
            end if
        end if
        
        -- If no title exists and body is empty, add title
        if noteTitle is "" and currentBody is "" then
            set noteTitle to "${NOTE_NAME}" & lineBreak & lineBreak
        end if
        
        -- Check for duplicate (compare with last entry from content without title)
        set lastEntryText to ""
        set lastEntryDate to ""
        if contentWithoutTitle is not "" then
            try
                set AppleScript's text item delimiters to return
                set contentLines to text items of contentWithoutTitle
                set AppleScript's text item delimiters to ""
                
                if (count of contentLines) > 1 then
                    set lastEntryText to item 2 of contentLines
                    set firstLine to item 1 of contentLines
                    if firstLine contains "[" and firstLine contains "]" then
                        set AppleScript's text item delimiters to "]"
                        set datePart to text item 1 of firstLine
                        set AppleScript's text item delimiters to "["
                        set datePart to text item 2 of datePart
                        set AppleScript's text item delimiters to ""
                        set lastEntryDate to datePart
                    end if
                end if
            end try
        end if
        
        -- Check if this is a duplicate
        set isDuplicate to false
        if lastEntryText is newTextContent then
            if lastEntryDate contains "${CURRENT_DATE}" then
                set timePart to text 12 thru 16 of lastEntryDate
                set currentTimeShort to text 1 thru 5 of "${CURRENT_TIME}"
                if timePart is currentTimeShort then
                    set isDuplicate to true
                end if
            end if
        end if
        
        if isDuplicate then
            return
        end if
        
        -- Prepare new content with proper formatting
        set lineBreak to return
        set newContent to "[${TIMESTAMP}]" & lineBreak & newTextContent & lineBreak & lineBreak
        
        -- Check if we need a day separator
        set needsDaySeparator to false
        if contentWithoutTitle is "" then
            set needsDaySeparator to true
        else
            -- Check if last entry was from a different day
            if lastEntryDate is not "" then
                set lastDate to text 1 thru 10 of lastEntryDate
                if lastDate is not "${CURRENT_DATE}" then
                    set needsDaySeparator to true
                end if
            end if
        end if
        
        -- Build the new body (title at top, then new content, then existing content)
        if needsDaySeparator then
            -- Day separator with proper spacing
            set lineBreak to return
            set daySeparator to lineBreak & lineBreak & "═══════════════════════════════════════" & lineBreak & "  ${CURRENT_DATE}" & lineBreak & "═══════════════════════════════════════" & lineBreak & lineBreak
            -- Add spacing between new content and separator if there's existing content
            if contentWithoutTitle is not "" then
                -- Trim leading newlines from existing content to avoid double spacing
                set trimmedContent to contentWithoutTitle
                try
                    repeat while (length of trimmedContent > 0) and (character 1 of trimmedContent is return)
                        set trimmedContent to text 2 thru -1 of trimmedContent
                    end repeat
                end try
                set newBody to noteTitle & newContent & daySeparator & trimmedContent
            else
                -- First entry, no need for extra spacing
                set newBody to noteTitle & newContent
            end if
        else
            -- No day separator needed, just add new content with proper spacing
            if contentWithoutTitle is not "" then
                -- Trim leading newlines from existing content to avoid double spacing
                set trimmedContent to contentWithoutTitle
                try
                    repeat while (length of trimmedContent > 0) and (character 1 of trimmedContent is return)
                        set trimmedContent to text 2 thru -1 of trimmedContent
                    end repeat
                end try
                set newBody to noteTitle & newContent & trimmedContent
            else
                set newBody to noteTitle & newContent
            end if
        end if
        
        -- Update the note
        -- Ensure newlines are preserved by explicitly setting the body
        -- Apple Notes may reformat, so we set it directly
        set body of targetNote to newBody as string
        
        -- Show notification
        display notification "Saved to ${NOTE_NAME}!" with title "Scribbledown" sound name "Glass"
    on error errMsg
        -- Silently fail if there's an error
        return
    end try
end tell
APPLESCRIPT_EOF


#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Scribbledown
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Saves selected text to scribbledown file without affecting clipboard

# Configuration
SCRIBBLE_FILE="$HOME/Desktop/Scribbledown/scribbledown.md"
SCRIBBLE_DIR=$(dirname "$SCRIBBLE_FILE")
mkdir -p "$SCRIBBLE_DIR"

# Rate limiting
LOCK_DIR="/tmp/scribbledown_lock"
TIMESTAMP_FILE="/tmp/scribbledown.timestamp"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi

trap 'rm -rf "$LOCK_DIR"' EXIT

CURRENT_TIMESTAMP=$(date +%s)
if [ -f "$TIMESTAMP_FILE" ]; then
    LAST_TIMESTAMP=$(cat "$TIMESTAMP_FILE")
    TIME_DIFF=$((CURRENT_TIMESTAMP - LAST_TIMESTAMP))
    if [ "$TIME_DIFF" -lt 1 ]; then
        exit 0
    fi
fi

echo "$CURRENT_TIMESTAMP" > "$TIMESTAMP_FILE"

# Get text from clipboard
TEXT_CONTENT=$(osascript 2>/dev/null <<'APPLESCRIPT_END'
on isNonTextData()
    try
        set clipInfo to (clipboard info) as string
        if clipInfo contains "PNGf" or clipInfo contains "TIFF" or clipInfo contains "JPEG" or clipInfo contains "GIFf" then
            return true
        end if
        if clipInfo contains "public.png" or clipInfo contains "public.tiff" or clipInfo contains "public.jpeg" then
            return true
        end if
        if clipInfo contains "furl" or clipInfo contains "public.file-url" then
            return true
        end if
    end try
    return false
end isNonTextData

try
    set savedClip to ""
    set hasClip to false
    
    try
        set savedClip to the clipboard as text
        if savedClip is not "" and savedClip is not missing value then
            set hasClip to true
        end if
    end try
    
    if isNonTextData() then
        return "BINARY_DATA"
    end if
    
    try
        tell application "System Events"
            keystroke "c" using command down
        end tell
        delay 0.15
    on error
    end try
    
    if isNonTextData() then
        if hasClip then
            try
                set the clipboard to savedClip
            end try
        end if
        return "BINARY_DATA"
    end if
    
    set newClip to ""
    try
        set newClip to the clipboard as text
    on error
        if hasClip then
            try
                set the clipboard to savedClip
            end try
        end if
        return "BINARY_DATA"
    end try
    
    if newClip is "" or newClip is missing value then
        if hasClip then
            try
                set the clipboard to savedClip
            end try
        end if
        return "NO_TEXT"
    end if
    
    set textLen to length of newClip
    if textLen > 10000 then
        set sample to text 1 thru 500 of newClip
        if sample contains "data" or sample contains "class" then
            if hasClip then
                try
                    set the clipboard to savedClip
                end try
            end if
            return "BINARY_DATA"
        end if
    end if
    
    if hasClip and newClip is not equal to savedClip then
        try
            set the clipboard to savedClip
        end try
        return newClip
    else
        return newClip
    end if
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

# Write to file
CURRENT_DATE=$(date +"%Y-%m-%d")
CURRENT_TIME=$(date +"%H:%M:%S")
TIMESTAMP="$CURRENT_DATE $CURRENT_TIME"

# Check for duplicate
if [ -f "$SCRIBBLE_FILE" ]; then
    LAST_ENTRY=$(grep -A 2 "^\[20" "$SCRIBBLE_FILE" 2>/dev/null | head -n 2 | tail -n 1)
    
    if [ "$LAST_ENTRY" = "$TEXT_CONTENT" ]; then
        LAST_TS=$(grep -m 1 "^\[20" "$SCRIBBLE_FILE" 2>/dev/null | sed 's/\[//' | sed 's/\]//')
        LAST_DATE=$(echo "$LAST_TS" | cut -d' ' -f1)
        LAST_TIME=$(echo "$LAST_TS" | cut -d' ' -f2 | cut -d: -f1,2)
        CURRENT_TIME_SHORT=$(echo "$CURRENT_TIME" | cut -d: -f1,2)
        if [ "$LAST_DATE" = "$CURRENT_DATE" ] && [ "$LAST_TIME" = "$CURRENT_TIME_SHORT" ]; then
            exit 0
        fi
    fi
fi

# Prepend new content
TEMP_FILE=$(mktemp)

if [ -f "$SCRIBBLE_FILE" ]; then
    FIRST_LINE=$(head -n 1 "$SCRIBBLE_FILE" 2>/dev/null)
    LAST_ENTRY_DATE=$(echo "$FIRST_LINE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1)
    if [ "$LAST_ENTRY_DATE" != "$CURRENT_DATE" ]; then
        echo "" >> "$TEMP_FILE"
        echo "═══════════════════════════════════════════════════════════════════" >> "$TEMP_FILE"
        echo "  $CURRENT_DATE" >> "$TEMP_FILE"
        echo "═══════════════════════════════════════════════════════════════════" >> "$TEMP_FILE"
        echo "" >> "$TEMP_FILE"
    fi
fi

echo "[$TIMESTAMP]" >> "$TEMP_FILE"
echo "$TEXT_CONTENT" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"

if [ -f "$SCRIBBLE_FILE" ]; then
    cat "$SCRIBBLE_FILE" >> "$TEMP_FILE"
else
    echo "═══════════════════════════════════════════════════════════════════" >> "$TEMP_FILE"
    echo "  $CURRENT_DATE" >> "$TEMP_FILE"
    echo "═══════════════════════════════════════════════════════════════════" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
fi

mv "$TEMP_FILE" "$SCRIBBLE_FILE"

osascript -e 'display notification "Saved!" with title "Scribbledown" sound name "Glass"' 2>/dev/null

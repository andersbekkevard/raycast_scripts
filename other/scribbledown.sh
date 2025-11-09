#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Scribbledown
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📝

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Saves clipboard content to scribbledown file

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
    # Find the most recent timestamp (first one in file)
    LAST_ENTRY_DATE=$(grep -m 1 "^\[20" "$SCRIBBLE_FILE" 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -n 1)
    
    # Only add day separator if this is a different day than the last entry
    if [ -n "$LAST_ENTRY_DATE" ] && [ "$LAST_ENTRY_DATE" != "$CURRENT_DATE" ]; then
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

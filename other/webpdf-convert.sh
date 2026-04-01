#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title WebPDF Convert
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📄
# @raycast.description Convert file:// PDF tab to localhost via webpdf

PORT=7432

# Get active tab URL from Comet
TAB_URL=$(osascript -e 'tell application "Comet" to return URL of active tab of front window' 2>/dev/null)

# Validate: must be file://*.pdf
if [[ ! "$TAB_URL" =~ ^file://.*\.pdf$ ]] && [[ ! "$TAB_URL" =~ ^file://.*\.PDF$ ]]; then
    osascript -e 'do shell script "afplay /System/Library/Sounds/Basso.aiff"'
    osascript -e 'display notification "Active tab is not a file:// PDF" with title "WebPDF"'
    exit 1
fi

# Convert file:// URL to localhost URL
# Strip file:// prefix, keep percent-encoding as-is
LOCAL_PATH="${TAB_URL#file://}"
LOCALHOST_URL="http://localhost:${PORT}/view${LOCAL_PATH}"

# Ensure server is running
if ! curl -sf "http://localhost:${PORT}/" > /dev/null 2>&1; then
    ~/.local/bin/webpdf serve &>/dev/null &
    for i in $(seq 1 15); do
        sleep 0.2
        if curl -sf "http://localhost:${PORT}/" > /dev/null 2>&1; then
            break
        fi
    done
fi

# Close current tab, then open localhost URL
osascript -e "
tell application \"Comet\"
    set frontWindow to front window
    set tabCount to count of tabs of frontWindow
    if tabCount > 1 then
        close active tab of frontWindow
    else
        close frontWindow
    end if
    delay 0.1
    if (count of windows) = 0 then
        make new window
    end if
    tell front window
        make new tab at end of tabs with properties {URL:\"${LOCALHOST_URL}\"}
    end tell
end tell
"

osascript -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff &"'

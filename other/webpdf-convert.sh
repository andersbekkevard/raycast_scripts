#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title WebPDF Convert
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📄
# @raycast.description Convert file:// PDF tab to localhost via webpdf

PORT=7432

# Pin the source tab so a slow conversion cannot navigate a different tab.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/browser.sh"
SOURCE_TAB=$(browser_control active) || exit 1
TAB_URL=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["url"])' "$SOURCE_TAB")

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

# Navigate the original tab in place.
browser_control navigate "$LOCALHOST_URL" --source "$SOURCE_TAB" || exit 1

osascript -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff &"'

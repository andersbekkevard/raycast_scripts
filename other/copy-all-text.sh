#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Copy All Text
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📋

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Copies all selectable text from the current window to clipboard

# Run via Shortcuts app which has its own accessibility permissions
shortcuts run "Copy All Text" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "Create a Shortcut named 'Copy All Text' with these actions:"
    echo "1. Select All (in frontmost app)"
    echo "2. Copy to Clipboard"
    exit 1
fi

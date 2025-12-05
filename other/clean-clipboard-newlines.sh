#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Clean Clipboard Newlines
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📋

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Replaces newlines in clipboard with spaces (useful for PDF text)

# Get clipboard, replace newlines with spaces, put back on clipboard
pbpaste | tr '\n' ' ' | pbcopy

echo "Clipboard cleaned"


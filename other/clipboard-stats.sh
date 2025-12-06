#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Clipboard Stats
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔠

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Shows word, character, and line count for clipboard

# Stream directly to wc - handles large clipboards without hitting arg limits
stats=$(pbpaste | wc)
lines=$(echo $stats | awk '{print $1}')
words=$(echo $stats | awk '{print $2}')
chars=$(echo $stats | awk '{print $3}')

echo "${words} words · ${chars} chars · ${lines} lines"


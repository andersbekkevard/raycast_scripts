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

clipboard=$(pbpaste)

chars=$(echo -n "$clipboard" | wc -c | tr -d ' ')
words=$(echo -n "$clipboard" | wc -w | tr -d ' ')
lines=$(echo -n "$clipboard" | wc -l | tr -d ' ')

echo "${words} words · ${chars} chars · ${lines} lines"


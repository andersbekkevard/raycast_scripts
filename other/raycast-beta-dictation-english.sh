#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Dictation: English (Beta)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🇬🇧
# @raycast.packageName Dictation

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Set Raycast Beta Dictation to English

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /usr/bin/swift "$SCRIPT_DIR/../lib/set-raycast-beta-dictation-language.swift" English


#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Standard Function Keys
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⌨️

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Toggles "Use F1, F2, etc. keys as standard function keys" and reports the new state

CURRENT=$(defaults read -g com.apple.keyboard.fnState 2>/dev/null || echo "0")

if [ "$CURRENT" = "1" ]; then
  defaults write -g com.apple.keyboard.fnState -bool false
  echo "Standard function keys: OFF (F-keys now trigger special features)"
else
  defaults write -g com.apple.keyboard.fnState -bool true
  echo "Standard function keys: ON (hold fn for special features)"
fi

echo "Note: may require logout/restart to take effect"

#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Caps Lock
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🔠

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Toggles Caps Lock on/off

STATE_FILE="/tmp/.caps_lock_state"

if [ -f "$STATE_FILE" ]; then
  NEW_STATE="false"
  rm "$STATE_FILE"
else
  NEW_STATE="true"
  touch "$STATE_FILE"
fi

swift -e "
import IOKit
import IOKit.hid

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
IOHIDSetModifierLockState(service, Int32(kIOHIDCapsLockState), $NEW_STATE)
IOObjectRelease(service)
"

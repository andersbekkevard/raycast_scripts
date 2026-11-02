#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Wi-Fi to 5 GHz
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 📶
# @raycast.argument1 { "type": "text", "placeholder": "SSID (default MIT SECURE)", "optional": true }

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Move Wi-Fi onto the strongest 5 GHz access point of the network

set -euo pipefail
# The command prints a current/best/joined summary; compact mode shows the last line.
exec "$HOME/.local/bin/wifi5g" ${1:+"$1"}

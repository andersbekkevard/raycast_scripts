#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube App Mode
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📺

# Documentation:
# @raycast.description Open current browser tab in app mode (borderless window, great for fullscreen YouTube)
# @raycast.author Anders Bekkevard

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/browser.sh"
browser_control app-mode

#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kokoro Speak Clipboard
# @raycast.mode silent

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Read the current clipboard aloud using the local Kokoro daemon

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/kokoro_paths.sh"

kokoro_require_cmd python3

if ! kokoro_health; then
  kokoro_fail "Kokoro daemon is off. Run Kokoro Toggle Daemon."
fi

python3 "$SCRIPT_DIR/kokoro_client.py" speak-clipboard

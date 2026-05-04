#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kokoro Stop Speaking
# @raycast.mode silent

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Stop the current Kokoro playback

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/kokoro_paths.sh"

kokoro_require_cmd python3

if ! kokoro_health; then
  echo "Kokoro daemon is off"
  exit 0
fi

python3 "$SCRIPT_DIR/kokoro_client.py" stop

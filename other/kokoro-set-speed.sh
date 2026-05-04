#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kokoro Set Default Speed
# @raycast.mode silent

# Optional parameters:
# @raycast.argument1 { "type": "text", "placeholder": "Speed 0.5-2.0, e.g. 1.15" }

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Set the default Kokoro speaking speed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/kokoro_paths.sh"

kokoro_require_cmd python3

python3 "$SCRIPT_DIR/kokoro_client.py" set-speed "$1"

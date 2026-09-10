#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Generate History Scripts
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ⚙️

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Regenerates all focus scripts from focus-configs.json with history support

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/lib/generate-focus-scripts.py"

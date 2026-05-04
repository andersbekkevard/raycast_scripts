#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kokoro Status
# @raycast.mode fullOutput

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Show local Kokoro daemon status, paths, and voices

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/kokoro_paths.sh"

kokoro_require_cmd python3

if ! kokoro_health; then
  echo "status: off"
  echo "base_url: $KOKORO_BASE_URL"
  echo "pid_file: $KOKORO_PID_FILE"
  echo "log_file: $KOKORO_LOG_FILE"
  echo "config_file: $KOKORO_CONFIG_FILE"
  exit 0
fi

python3 "$SCRIPT_DIR/kokoro_client.py" status

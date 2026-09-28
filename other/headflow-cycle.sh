#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Cycle HeadFlow Mode
# @raycast.mode silent
# @raycast.packageName HeadFlow
# @raycast.author Anders Bekkevard
# @raycast.description Cycle Cursor, Continuous, and Auto-read modes

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/../lib/headflow-control.sh" cycle

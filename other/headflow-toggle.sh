#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Toggle HeadFlow
# @raycast.mode silent
# @raycast.packageName HeadFlow
# @raycast.author Anders Bekkevard
# @raycast.description Turn HeadFlow control on or off

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/../lib/headflow-control.sh" toggle

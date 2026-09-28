#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Turn HeadFlow On
# @raycast.mode silent
# @raycast.packageName HeadFlow
# @raycast.author Anders Bekkevard
# @raycast.description Enable HeadFlow control

set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$script_dir/../lib/headflow-control.sh" resume

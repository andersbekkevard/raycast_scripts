#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Recalibrate HeadFlow
# @raycast.mode silent
# @raycast.packageName HeadFlow
# @raycast.author Anders Bekkevard
# @raycast.description Set your current head position as neutral

set -euo pipefail
"$HOME/.local/bin/headflow" calibrate --json | /usr/bin/python3 -c '
import json,sys
result=json.load(sys.stdin)
if not result.get("runtime_acknowledged"):
    print("HeadFlow did not acknowledge calibration. Check that it is running.",file=sys.stderr)
    sys.exit(1)
print("HeadFlow calibration requested; hold your head in its neutral position.")
'

#!/bin/bash
set -euo pipefail

command_name="${1:?HeadFlow command required}"
case "$command_name" in
  cycle|toggle|pause|resume) ;;
  *) echo "Unknown HeadFlow command: $command_name" >&2; exit 2 ;;
esac

headflow="$HOME/.local/bin/headflow"
if [[ ! -x "$headflow" ]]; then
  echo "HeadFlow CLI is missing: $headflow" >&2
  exit 1
fi

"$headflow" "$command_name" --json | /usr/bin/python3 -c '
import json, sys
result = json.load(sys.stdin)
settings = result["settings"]
if "scrollModeRaw" in settings:
    mode = {0: "Continuous", 2: "Auto-read", 3: "Cursor"}[settings["scrollModeRaw"]]
    message = f"HeadFlow mode: {mode}"
else:
    message = "HeadFlow: on" if settings["isHeadScrollingEnabled"] else "HeadFlow: off"
if not result["runtime_acknowledged"]:
    message += " (saved; app did not acknowledge)"
print(message)
'

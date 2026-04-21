#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube Transcript Clipboard
# @raycast.mode silent

# Optional parameters:
# @raycast.packageName Clipboard
# @raycast.icon ▶️

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Reads a YouTube URL from the clipboard, copies the transcript, and pastes it.

set -euo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PYTHON_SCRIPT="$SCRIPT_DIR/youtube-transcript-clipboard.py"

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is not available in Raycast's PATH"
  exit 1
fi

exec uv run --script "$PYTHON_SCRIPT" "$@"

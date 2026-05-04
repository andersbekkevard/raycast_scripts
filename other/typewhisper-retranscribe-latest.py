#!/usr/bin/env python3

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title TypeWhisper Retranscribe Latest
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎙️
# @raycast.packageName TypeWhisper

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Retranscribe the most recent saved TypeWhisper WAV, then copy and paste the result.

from __future__ import annotations

import argparse
import sys
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from typewhisper_retranscribe_lib import copy_to_clipboard, load_recent_audio_entries, paste_clipboard, transcribe_audio


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Retranscribe the most recent saved TypeWhisper WAV.")
    parser.add_argument("--no-paste", action="store_true", help="Copy to clipboard but do not press Cmd+V.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        entry = load_recent_audio_entries(limit=1)[0]
        text = transcribe_audio(entry.audio_path)
        copy_to_clipboard(text)
        if not args.no_paste:
            paste_clipboard()
    except Exception as exc:  # noqa: BLE001
        print(str(exc), file=sys.stderr)
        return 1

    print(f"Retranscribed latest WAV: {entry.audio_path.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

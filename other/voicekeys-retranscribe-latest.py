#!/usr/bin/env python3

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title VoiceKeys Retranscribe Latest
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🎙️
# @raycast.packageName Voice Keys

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Retry the latest saved Voice Keys recording using its native engine and paste into the focused app.

"""Delegate transcription, history, failure UI, and safe insertion to Voice Keys."""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check readiness without starting a retry.")
    args = parser.parse_args()
    app = Path.home() / "Applications/Voice Keys.app"
    control = app / "Contents/MacOS/voice-keys-control"
    status = Path.home() / "Library/Application Support/VoiceKeys/status.json"
    try:
        if not control.is_file():
            raise RuntimeError("Voice Keys is not installed in ~/Applications.")
        running = subprocess.run(["/usr/bin/pgrep", "-x", "VoiceKeysApp"], capture_output=True).returncode == 0
        if not running:
            if args.check:
                raise RuntimeError("Voice Keys is installed but is not running.")
            launched_at = time.time_ns()
            subprocess.run(["/usr/bin/open", "-g", str(app)], check=True)
            deadline = time.monotonic() + 10
            while not status.exists() or status.stat().st_mtime_ns < launched_at:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Voice Keys did not become ready. Open it and try again.")
                time.sleep(0.1)
        # Silent Raycast commands dismiss the launcher. Allow focus to return
        # before the engine captures the destination for its normal safe paste.
        if not args.check:
            time.sleep(0.35)
        state = json.loads(status.read_text())
        if state.get("dictation_busy"):
            raise RuntimeError("Finish the current Voice Keys dictation before retrying.")
        if not str(state.get("dictation_backend", "")).startswith("native-"):
            raise RuntimeError("The native Voice Keys dictation engine is not ready.")
        if args.check:
            print("Voice Keys native retranscription command is ready.")
            return 0
        subprocess.run([str(control), "retry-dictation"], check=True, capture_output=True, text=True)
        print("Retry requested. Voice Keys will transcribe the saved recording and insert the result.")
        return 0
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Upload Clipboard Image
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖼️

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Uploads the clipboard image to tmpfiles.org, copies the URL, and pastes it

set -euo pipefail

tmpdir="$(mktemp -d /tmp/upload-clipboard-image.XXXXXX)"
swift_script="$tmpdir/export.swift"
image_file="$tmpdir/clipboard-image.png"
response_file="$tmpdir/response.json"

cleanup() {
  rm -rf "$tmpdir"
}

trap cleanup EXIT

cat >"$swift_script" <<'SWIFT'
import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let pasteboard = NSPasteboard.general

guard
  let sourceData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
  let image = NSImage(data: sourceData),
  let tiffData = image.tiffRepresentation,
  let bitmap = NSBitmapImageRep(data: tiffData),
  let pngData = bitmap.representation(using: .png, properties: [:])
else {
  FileHandle.standardError.write(Data("Clipboard does not contain an image\n".utf8))
  exit(1)
}

do {
  try pngData.write(to: URL(fileURLWithPath: outputPath))
} catch {
  FileHandle.standardError.write(Data("Failed to export clipboard image: \(error)\n".utf8))
  exit(1)
}
SWIFT

if ! swiftc "$swift_script" -o "$tmpdir/export-image" >/dev/null 2>&1; then
  echo "Failed to prepare clipboard image exporter"
  exit 1
fi

if ! "$tmpdir/export-image" "$image_file" 2>/dev/null; then
  echo "Clipboard does not contain an image"
  exit 1
fi

if ! curl -fsS -F "file=@$image_file" https://tmpfiles.org/api/v1/upload >"$response_file"; then
  echo "Upload failed"
  exit 1
fi

url="$(
  python3 - "$response_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    payload = json.load(fh)

url = payload.get("data", {}).get("url")
if not url:
    raise SystemExit(1)

print(url.replace("http://", "https://", 1))
PY
)"

if [ -z "$url" ]; then
  echo "Upload succeeded, but no URL was returned"
  exit 1
fi

printf '%s' "$url" | pbcopy

# Give Raycast a moment to close before pasting into the previously focused app.
if ! osascript >/dev/null 2>&1 <<'APPLESCRIPT'
delay 0.35
tell application "System Events"
  keystroke "v" using command down
end tell
APPLESCRIPT
then
  echo "Uploaded, but automatic paste failed"
  exit 1
fi

echo "$url"

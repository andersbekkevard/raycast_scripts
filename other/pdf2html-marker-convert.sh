#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title PDF2HTML Marker Convert
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📗
# @raycast.description Convert file:// PDF tab to semantic HTML via marker

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

PORT=7434
CACHE_DIR="$HOME/.cache/marker-serve"
LOG_FILE="$CACHE_DIR/log"
MAP_FILE="$CACHE_DIR/mappings.tsv"

mkdir -p "$CACHE_DIR"
# Silence stdout/stderr so Raycast can't raise notifications from subprocess output
exec >>"$LOG_FILE" 2>&1
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"; }

notify() {
    osascript -e "display notification \"$1\" with title \"Marker\"" >/dev/null 2>&1
}

fail() {
    log "FAIL: $1"
    osascript -e 'do shell script "afplay /System/Library/Sounds/Basso.aiff &"' >/dev/null 2>&1
    notify "$1"
    exit 1
}

# Get active tab URL from Comet
TAB_URL=$(osascript -e 'tell application "Comet" to return URL of active tab of front window' 2>/dev/null)

if [[ ! "$TAB_URL" =~ ^file://.*\.[pP][dD][fF]$ ]]; then
    fail "Active tab is not a file:// PDF"
fi

ENCODED_PATH="${TAB_URL#file://}"
LOCAL_PATH=$(python3 -c "import sys, urllib.parse as u; print(u.unquote(sys.argv[1]))" "$ENCODED_PATH")
[[ -f "$LOCAL_PATH" ]] || fail "PDF not found on disk"

MARKER_BIN=$(command -v marker_single 2>/dev/null)
[[ -n "$MARKER_BIN" ]] || fail "marker_single not found — pip install marker-pdf"

# Stable cache key (content hash)
HASH=$(shasum -a 256 "$LOCAL_PATH" | awk '{print $1}' | head -c 16)
PDF_NAME=$(basename "$LOCAL_PATH")
STEM="${PDF_NAME%.*}"
OUT_DIR="$CACHE_DIR/$HASH"
OUT_HTML="$OUT_DIR/$STEM/$STEM.html"
mkdir -p "$OUT_DIR"

# Convert on miss
if [[ ! -f "$OUT_HTML" ]]; then
    notify "Marker converting $PDF_NAME… (first run downloads models)"
    log "convert start: $LOCAL_PATH -> $OUT_HTML"
    TORCH_DEVICE=mps "$MARKER_BIN" "$LOCAL_PATH" \
        --output_dir "$OUT_DIR" \
        --output_format html >>"$LOG_FILE" 2>&1 || fail "marker conversion failed (see $LOG_FILE)"
    log "convert done: $OUT_HTML"
fi

# Ensure static server is up
if ! curl -sf "http://localhost:${PORT}/" >/dev/null 2>&1; then
    log "starting http.server on :$PORT rooted at $CACHE_DIR"
    (cd "$CACHE_DIR" && nohup python3 -m http.server "$PORT" >>"$LOG_FILE" 2>&1 &)
    for i in $(seq 1 25); do
        sleep 0.2
        curl -sf "http://localhost:${PORT}/" >/dev/null 2>&1 && break
    done
fi

ENCODED_STEM=$(python3 -c "import sys, urllib.parse as u; print(u.quote(sys.argv[1]))" "$STEM")
URL="http://localhost:${PORT}/${HASH}/${ENCODED_STEM}/${ENCODED_STEM}.html"

# Upsert pdf→html mapping
{
    if [[ -f "$MAP_FILE" ]]; then
        awk -F'\t' -v p="$LOCAL_PATH" '$2 != p' "$MAP_FILE"
    fi
    printf '%s\t%s\t%s\t%s\n' "$(date -Iseconds)" "$LOCAL_PATH" "$HASH" "$OUT_HTML"
} > "$MAP_FILE.tmp" && mv "$MAP_FILE.tmp" "$MAP_FILE"

# Navigate current tab in-place so back-button returns to the source PDF
osascript -e "
tell application \"Comet\"
    set URL of active tab of front window to \"${URL}\"
end tell
" >/dev/null 2>&1

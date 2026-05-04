#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

KOKORO_APP_NAME="kokoro-clipboard"
KOKORO_HOST="${KOKORO_HOST:-127.0.0.1}"
KOKORO_PORT="${KOKORO_PORT:-8767}"
KOKORO_BASE_URL="http://${KOKORO_HOST}:${KOKORO_PORT}"
KOKORO_ONNX_PROVIDER="${KOKORO_ONNX_PROVIDER:-CoreMLExecutionProvider}"
export ONNX_PROVIDER="${ONNX_PROVIDER:-$KOKORO_ONNX_PROVIDER}"

KOKORO_SHARE_DIR="${KOKORO_SHARE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/${KOKORO_APP_NAME}}"
KOKORO_CACHE_DIR="${KOKORO_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/${KOKORO_APP_NAME}}"
KOKORO_STATE_DIR="${KOKORO_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/${KOKORO_APP_NAME}}"

KOKORO_MODEL_DIR="${KOKORO_MODEL_DIR:-$KOKORO_SHARE_DIR/models}"
KOKORO_CONFIG_FILE="${KOKORO_CONFIG_FILE:-$KOKORO_SHARE_DIR/config.json}"
KOKORO_PID_FILE="${KOKORO_PID_FILE:-$KOKORO_STATE_DIR/daemon.pid}"
KOKORO_LOG_FILE="${KOKORO_LOG_FILE:-$KOKORO_STATE_DIR/daemon.log}"
KOKORO_LAUNCHD_LABEL="${KOKORO_LAUNCHD_LABEL:-local.kokoro-clipboard}"
KOKORO_LAUNCHD_PLIST="${KOKORO_LAUNCHD_PLIST:-$KOKORO_SHARE_DIR/launchd/${KOKORO_LAUNCHD_LABEL}.plist}"

mkdir -p "$KOKORO_MODEL_DIR" "$KOKORO_CACHE_DIR/audio" "$KOKORO_STATE_DIR" "$(dirname "$KOKORO_LAUNCHD_PLIST")"

kokoro_notify() {
  local message="$1"
  local escaped="${message//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  osascript -e "display notification \"$escaped\" with title \"Kokoro Clipboard\"" >/dev/null 2>&1 || true
}

kokoro_fail() {
  local message="$1"
  echo "$message" >&2
  kokoro_notify "$message"
  exit 1
}

kokoro_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || kokoro_fail "Missing required command: $1"
}

kokoro_health() {
  curl -fsS --max-time 1 "$KOKORO_BASE_URL/status" >/dev/null 2>&1
}

kokoro_pid_alive() {
  [[ -f "$KOKORO_PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$KOKORO_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

kokoro_pid_matches() {
  [[ -f "$KOKORO_PID_FILE" ]] || return 1
  local pid command_line
  pid="$(cat "$KOKORO_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$command_line" == *"kokoro_daemon.py"* || "$command_line" == *"uv run"* ]]
}

kokoro_launchd_loaded() {
  command -v launchctl >/dev/null 2>&1 || return 1
  launchctl print "gui/$(id -u)/$KOKORO_LAUNCHD_LABEL" >/dev/null 2>&1
}

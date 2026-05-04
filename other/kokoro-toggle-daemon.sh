#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kokoro Toggle Daemon
# @raycast.mode silent

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Start or stop the local Kokoro clipboard TTS daemon

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/kokoro_paths.sh"

kokoro_require_cmd uv
kokoro_require_cmd curl

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  printf '%s' "$value"
}

write_launchd_plist() {
  local uv_bin
  uv_bin="$(command -v uv)"
  cat >"$KOKORO_LAUNCHD_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(xml_escape "$KOKORO_LAUNCHD_LABEL")</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$uv_bin")</string>
    <string>run</string>
    <string>--script</string>
    <string>$(xml_escape "$SCRIPT_DIR/kokoro_daemon.py")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$(xml_escape "$PATH")</string>
    <key>KOKORO_HOST</key>
    <string>$(xml_escape "$KOKORO_HOST")</string>
    <key>KOKORO_PORT</key>
    <string>$(xml_escape "$KOKORO_PORT")</string>
    <key>KOKORO_ONNX_PROVIDER</key>
    <string>$(xml_escape "$KOKORO_ONNX_PROVIDER")</string>
    <key>ONNX_PROVIDER</key>
    <string>$(xml_escape "$ONNX_PROVIDER")</string>
    <key>KOKORO_SHARE_DIR</key>
    <string>$(xml_escape "$KOKORO_SHARE_DIR")</string>
    <key>KOKORO_CACHE_DIR</key>
    <string>$(xml_escape "$KOKORO_CACHE_DIR")</string>
    <key>KOKORO_STATE_DIR</key>
    <string>$(xml_escape "$KOKORO_STATE_DIR")</string>
    <key>KOKORO_MODEL_DIR</key>
    <string>$(xml_escape "$KOKORO_MODEL_DIR")</string>
    <key>KOKORO_CONFIG_FILE</key>
    <string>$(xml_escape "$KOKORO_CONFIG_FILE")</string>
    <key>KOKORO_PID_FILE</key>
    <string>$(xml_escape "$KOKORO_PID_FILE")</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>$(xml_escape "$SCRIPT_DIR")</string>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$KOKORO_LOG_FILE")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$KOKORO_LOG_FILE")</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
</dict>
</plist>
EOF
}

stop_daemon() {
  if kokoro_health; then
    curl -fsS -X POST "$KOKORO_BASE_URL/shutdown" >/dev/null 2>&1 || true
  fi

  if kokoro_launchd_loaded; then
    launchctl bootout "gui/$(id -u)/$KOKORO_LAUNCHD_LABEL" >/dev/null 2>&1 || \
      launchctl bootout "gui/$(id -u)" "$KOKORO_LAUNCHD_PLIST" >/dev/null 2>&1 || true
  fi

  for _ in $(seq 1 40); do
    if ! kokoro_pid_alive && ! kokoro_health && ! kokoro_launchd_loaded; then
      rm -f "$KOKORO_PID_FILE"
      echo "Kokoro daemon stopped"
      kokoro_notify "Kokoro daemon stopped"
      return 0
    fi
    sleep 0.25
  done

  if kokoro_pid_alive && kokoro_pid_matches; then
    pid="$(cat "$KOKORO_PID_FILE")"
    kill "$pid" >/dev/null 2>&1 || true
    sleep 0.5
  fi

  rm -f "$KOKORO_PID_FILE"
  echo "Kokoro daemon stopped"
  kokoro_notify "Kokoro daemon stopped"
}

start_daemon() {
  if kokoro_health; then
    echo "Kokoro daemon already running"
    kokoro_notify "Kokoro daemon already running"
    return 0
  fi

  if kokoro_launchd_loaded; then
    launchctl kickstart -k "gui/$(id -u)/$KOKORO_LAUNCHD_LABEL" >/dev/null 2>&1 || true
  fi

  if kokoro_pid_alive && ! kokoro_pid_matches; then
    kokoro_fail "PID file points to an unrelated process: $(cat "$KOKORO_PID_FILE")"
  fi

  rm -f "$KOKORO_PID_FILE"
  if command -v launchctl >/dev/null 2>&1; then
    write_launchd_plist
    if kokoro_launchd_loaded; then
      launchctl kickstart -k "gui/$(id -u)/$KOKORO_LAUNCHD_LABEL" >/dev/null 2>&1 || true
    else
      launchctl bootstrap "gui/$(id -u)" "$KOKORO_LAUNCHD_PLIST"
    fi
  else
    nohup uv run --script "$SCRIPT_DIR/kokoro_daemon.py" >>"$KOKORO_LOG_FILE" 2>&1 &
    echo "$!" >"$KOKORO_PID_FILE"
  fi

  for _ in $(seq 1 80); do
    if kokoro_health; then
      echo "Kokoro daemon started"
      kokoro_notify "Kokoro daemon started"
      return 0
    fi
    sleep 0.25
  done

  echo "Kokoro daemon is starting. First run may install dependencies and download the model."
  echo "Log: $KOKORO_LOG_FILE"
  kokoro_notify "Kokoro daemon is starting"
}

if kokoro_health || kokoro_pid_alive || kokoro_launchd_loaded; then
  stop_daemon
else
  start_daemon
fi

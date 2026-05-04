#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

APP_NAME = "kokoro-clipboard"
HOME = Path.home()
SHARE_DIR = Path(
    os.environ.get(
        "KOKORO_SHARE_DIR",
        str(Path(os.environ.get("XDG_DATA_HOME", HOME / ".local" / "share")) / APP_NAME),
    )
).expanduser()
STATE_DIR = Path(
    os.environ.get(
        "KOKORO_STATE_DIR",
        str(Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state")) / APP_NAME),
    )
).expanduser()

CONFIG_FILE = Path(os.environ.get("KOKORO_CONFIG_FILE", SHARE_DIR / "config.json")).expanduser()
BASE_URL = "http://{}:{}".format(os.environ.get("KOKORO_HOST", "127.0.0.1"), os.environ.get("KOKORO_PORT", "8767"))

DEFAULT_CONFIG: dict[str, Any] = {
    "model_variant": "fp32",
    "voice": "af_heart",
    "speed": 1.0,
    "lang": "en-us",
}


def request_json(method: str, path: str, payload: dict[str, Any] | None = None, timeout: float = 60.0) -> dict[str, Any]:
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"

    request = urllib.request.Request(BASE_URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(body)
            raise SystemExit(parsed.get("error", body))
        except json.JSONDecodeError:
            raise SystemExit(body or str(exc)) from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Kokoro daemon is off. Run Kokoro Toggle Daemon. ({exc.reason})") from exc


def pbpaste() -> str:
    try:
        result = subprocess.run(["/usr/bin/pbpaste"], check=True, stdout=subprocess.PIPE)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"pbpaste failed: {exc}") from exc
    return result.stdout.decode("utf-8", errors="replace")


def load_config() -> dict[str, Any]:
    if not CONFIG_FILE.exists():
        return dict(DEFAULT_CONFIG)
    try:
        with CONFIG_FILE.open("r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return dict(DEFAULT_CONFIG)
    config = dict(DEFAULT_CONFIG)
    config.update(loaded)
    return config


def save_config(config: dict[str, Any]) -> None:
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_FILE.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2, sort_keys=True)
        handle.write("\n")
    tmp.replace(CONFIG_FILE)


def parse_speed(value: str | None) -> float | None:
    if value is None or not value.strip():
        return None
    try:
        speed = float(value)
    except ValueError as exc:
        raise SystemExit("Speed must be a number between 0.5 and 2.0") from exc
    if speed < 0.5 or speed > 2.0:
        raise SystemExit("Speed must be between 0.5 and 2.0")
    return speed


def command_speak_clipboard(args: list[str]) -> None:
    voice = args[0].strip() if len(args) >= 1 and args[0].strip() else None
    speed = parse_speed(args[1] if len(args) >= 2 else None)
    status = request_json("GET", "/status", timeout=3.0)
    if status.get("busy") or status.get("generation_running") or status.get("playback_running"):
        result = request_json("POST", "/stop", {}, timeout=5.0)
        previous = result.get("previous_state", "active")
        if result.get("cancel_requested"):
            print("Stopping Kokoro generation")
        elif result.get("stopped"):
            print(f"Stopped Kokoro {previous}")
        else:
            print("Kokoro was idle")
        return

    text = pbpaste()
    if not text.strip():
        raise SystemExit("Clipboard is empty")
    payload: dict[str, Any] = {"text": text}
    if voice:
        payload["voice"] = voice
    if speed is not None:
        payload["speed"] = speed
    result = request_json("POST", "/speak", payload, timeout=300.0)
    if not result.get("ok"):
        raise SystemExit(result.get("error", "Kokoro speak failed"))
    if result.get("action") in {"stopped", "cancelled", "idle"}:
        print("Stopped Kokoro" if result.get("stopped") else "Kokoro was idle")
        return
    print(
        "Speaking {} chars with {} ({:.2f}s generation)".format(
            result.get("chars"),
            result.get("voice"),
            float(result.get("generation_seconds", 0.0)),
        )
    )


def command_stop(_args: list[str]) -> None:
    result = request_json("POST", "/stop", {}, timeout=5.0)
    if result.get("cancel_requested"):
        print("Stopping Kokoro generation")
    elif result.get("stopped"):
        print("Stopped speaking")
    else:
        print("Nothing was playing")


def command_status(_args: list[str]) -> None:
    result = request_json("GET", "/status", timeout=5.0)
    voices = result.get("voices", [])
    print(f"status: on")
    print(f"pid: {result.get('pid')}")
    print(f"uptime_seconds: {result.get('uptime_seconds')}")
    print(f"model_variant: {result.get('model_variant')}")
    print(f"onnx_provider: {result.get('onnx_provider')}")
    print(f"voice: {result.get('voice')}")
    print(f"speed: {result.get('speed')}")
    print(f"lang: {result.get('lang')}")
    print(f"state: {result.get('state')}")
    print(f"busy: {result.get('busy')}")
    print(f"generation_running: {result.get('generation_running')}")
    print(f"active_elapsed_seconds: {result.get('active_elapsed_seconds')}")
    print(f"active_batch: {result.get('active_batch')}/{result.get('active_batches')}")
    print(f"playback_running: {result.get('playback_running')}")
    print(f"model_path: {result.get('model_path')}")
    print(f"config_path: {result.get('config_path')}")
    print(f"voices_count: {result.get('voices_count')}")
    print("voices: " + ", ".join(voices))


def command_set_voice(args: list[str]) -> None:
    if not args or not args[0].strip():
        raise SystemExit("Voice is required")
    voice = args[0].strip()
    config = load_config()
    config["voice"] = voice
    save_config(config)

    try:
        result = request_json("POST", "/config", {"voice": voice}, timeout=2.0)
    except SystemExit:
        result = {"ok": False}

    suffix = " and live daemon" if result.get("ok") else ""
    print(f"Default Kokoro voice set to {voice}{suffix}")


def command_set_speed(args: list[str]) -> None:
    speed = parse_speed(args[0] if args else None)
    if speed is None:
        raise SystemExit("Speed is required")
    config = load_config()
    config["speed"] = speed
    save_config(config)
    try:
        request_json("POST", "/config", {"speed": speed}, timeout=2.0)
    except SystemExit:
        pass
    print(f"Default Kokoro speed set to {speed}")


def command_config_path(_args: list[str]) -> None:
    print(str(CONFIG_FILE))


COMMANDS = {
    "speak-clipboard": command_speak_clipboard,
    "stop": command_stop,
    "status": command_status,
    "set-voice": command_set_voice,
    "set-speed": command_set_speed,
    "config-path": command_config_path,
}


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print("Usage: kokoro_client.py {} [args...]".format("|".join(sorted(COMMANDS))), file=sys.stderr)
        return 2
    COMMANDS[argv[1]](argv[2:])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

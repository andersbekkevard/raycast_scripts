#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10,<3.14"
# dependencies = [
#   "kokoro-onnx==0.5.0",
# ]
# ///

from __future__ import annotations

import json
import logging
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import numpy as np
from kokoro_onnx import Kokoro
from kokoro_onnx.trim import trim as trim_audio

APP_NAME = "kokoro-clipboard"
HOST = os.environ.get("KOKORO_HOST", "127.0.0.1")
PORT = int(os.environ.get("KOKORO_PORT", "8767"))
ONNX_PROVIDER = os.environ.get("ONNX_PROVIDER", "CPUExecutionProvider")

HOME = Path.home()
SHARE_DIR = Path(
    os.environ.get(
        "KOKORO_SHARE_DIR",
        str(Path(os.environ.get("XDG_DATA_HOME", HOME / ".local" / "share")) / APP_NAME),
    )
).expanduser()
CACHE_DIR = Path(
    os.environ.get(
        "KOKORO_CACHE_DIR",
        str(Path(os.environ.get("XDG_CACHE_HOME", HOME / ".cache")) / APP_NAME),
    )
).expanduser()
STATE_DIR = Path(
    os.environ.get(
        "KOKORO_STATE_DIR",
        str(Path(os.environ.get("XDG_STATE_HOME", HOME / ".local" / "state")) / APP_NAME),
    )
).expanduser()

MODEL_DIR = Path(os.environ.get("KOKORO_MODEL_DIR", SHARE_DIR / "models")).expanduser()
CONFIG_FILE = Path(os.environ.get("KOKORO_CONFIG_FILE", SHARE_DIR / "config.json")).expanduser()
PID_FILE = Path(os.environ.get("KOKORO_PID_FILE", STATE_DIR / "daemon.pid")).expanduser()
AUDIO_DIR = CACHE_DIR / "audio"

MODEL_VARIANTS = {
    "fp32": {
        "filename": "kokoro-v1.0.onnx",
        "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx",
    },
    "fp16": {
        "filename": "kokoro-v1.0.fp16.onnx",
        "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.fp16.onnx",
    },
    "int8": {
        "filename": "kokoro-v1.0.int8.onnx",
        "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.int8.onnx",
    },
}

VOICES_ASSET = {
    "filename": "voices-v1.0.bin",
    "url": "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin",
}

DEFAULT_CONFIG: dict[str, Any] = {
    "model_variant": "fp32",
    "voice": "af_heart",
    "speed": 1.0,
    "lang": "en-us",
}


def configure_logging() -> None:
    logging.basicConfig(
        level=os.environ.get("KOKORO_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )


def ensure_dirs() -> None:
    for path in (SHARE_DIR, MODEL_DIR, AUDIO_DIR, STATE_DIR):
        path.mkdir(parents=True, exist_ok=True)


def load_config() -> dict[str, Any]:
    if not CONFIG_FILE.exists():
        save_config(DEFAULT_CONFIG)
        return dict(DEFAULT_CONFIG)

    try:
        with CONFIG_FILE.open("r", encoding="utf-8") as handle:
            loaded = json.load(handle)
    except (OSError, json.JSONDecodeError):
        logging.warning("Invalid config at %s; replacing with defaults", CONFIG_FILE)
        save_config(DEFAULT_CONFIG)
        return dict(DEFAULT_CONFIG)

    config = dict(DEFAULT_CONFIG)
    config.update({key: value for key, value in loaded.items() if value is not None})
    return config


def save_config(config: dict[str, Any]) -> None:
    ensure_dirs()
    tmp = CONFIG_FILE.with_suffix(".json.tmp")
    with tmp.open("w", encoding="utf-8") as handle:
        json.dump(config, handle, indent=2, sort_keys=True)
        handle.write("\n")
    tmp.replace(CONFIG_FILE)


def download_file(url: str, target: Path) -> None:
    if target.exists() and target.stat().st_size > 0:
        return

    logging.info("Downloading %s", target.name)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{target.name}.", dir=str(target.parent))
    os.close(fd)
    tmp_path = Path(tmp_name)
    try:
        with urllib.request.urlopen(url) as response, tmp_path.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
        tmp_path.replace(target)
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def resolve_assets(config: dict[str, Any]) -> tuple[Path, Path, str]:
    variant = os.environ.get("KOKORO_MODEL_VARIANT", str(config.get("model_variant", "fp32")))
    if variant not in MODEL_VARIANTS:
        raise ValueError(f"Unknown model variant {variant!r}. Use one of: {', '.join(MODEL_VARIANTS)}")

    model_asset = MODEL_VARIANTS[variant]
    model_path = MODEL_DIR / model_asset["filename"]
    voices_path = MODEL_DIR / VOICES_ASSET["filename"]
    download_file(model_asset["url"], model_path)
    download_file(VOICES_ASSET["url"], voices_path)
    return model_path, voices_path, variant


def write_wav(path: Path, samples: np.ndarray, sample_rate: int) -> None:
    audio = np.asarray(samples, dtype=np.float32).reshape(-1)
    audio = np.nan_to_num(audio, nan=0.0, posinf=0.0, neginf=0.0)
    audio = np.clip(audio, -1.0, 1.0)
    pcm = (audio * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(pcm.tobytes())


class Runtime:
    def __init__(self) -> None:
        self.started_at = time.time()
        self.config = load_config()
        model_path, voices_path, variant = resolve_assets(self.config)
        self.model_variant = variant
        self.model_path = model_path
        self.voices_path = voices_path
        logging.info("Loading Kokoro model %s", model_path)
        self.kokoro = Kokoro(str(model_path), str(voices_path))
        self.voices = self.kokoro.get_voices()
        self.generation_lock = threading.Lock()
        self.playback_lock = threading.Lock()
        self.state_lock = threading.RLock()
        self.stop_requested = threading.Event()
        self.state = "idle"
        self.active_started_at: float | None = None
        self.active_chars = 0
        self.active_voice: str | None = None
        self.active_speed: float | None = None
        self.active_lang: str | None = None
        self.active_batch = 0
        self.active_batches = 0
        self.playback_process: subprocess.Popen[bytes] | None = None
        self.last_audio_path: Path | None = None
        logging.info("Kokoro ready with %d voices", len(self.voices))

    def reload_config(self) -> dict[str, Any]:
        self.config = load_config()
        return self.config

    def save_config_update(self, updates: dict[str, Any]) -> dict[str, Any]:
        config = load_config()
        config.update(updates)
        save_config(config)
        self.config = config
        return config

    def _set_state(
        self,
        state: str,
        *,
        chars: int | None = None,
        voice: str | None = None,
        speed: float | None = None,
        lang: str | None = None,
        batch: int | None = None,
        batches: int | None = None,
    ) -> None:
        with self.state_lock:
            self.state = state
            if state == "idle":
                self.active_started_at = None
                self.active_chars = 0
                self.active_voice = None
                self.active_speed = None
                self.active_lang = None
                self.active_batch = 0
                self.active_batches = 0
                return

            if self.active_started_at is None:
                self.active_started_at = time.time()
            if chars is not None:
                self.active_chars = chars
            if voice is not None:
                self.active_voice = voice
            if speed is not None:
                self.active_speed = speed
            if lang is not None:
                self.active_lang = lang
            if batch is not None:
                self.active_batch = batch
            if batches is not None:
                self.active_batches = batches

    def _poll_playback_locked(self) -> bool:
        if self.playback_process is None:
            return False
        running = self.playback_process.poll() is None
        if not running:
            self.playback_process = None
            with self.state_lock:
                if self.state == "playing":
                    self._set_state("idle")
        return running

    def is_busy(self) -> bool:
        with self.state_lock:
            if self.state != "idle":
                return True
        with self.playback_lock:
            return self._poll_playback_locked()

    def stop_playback(self) -> bool:
        with self.playback_lock:
            proc = self.playback_process
            if proc is None or proc.poll() is not None:
                self.playback_process = None
                with self.state_lock:
                    if self.state == "playing":
                        self._set_state("idle")
                return False
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
            self.playback_process = None
        with self.state_lock:
            if self.state == "playing":
                self._set_state("idle")
        return True

    def stop(self) -> dict[str, Any]:
        with self.state_lock:
            previous_state = self.state
        if previous_state == "generating":
            self.stop_requested.set()
        else:
            self.stop_requested.clear()
        stopped_playback = self.stop_playback()
        cancel_requested = previous_state == "generating"
        if previous_state == "idle" and not stopped_playback:
            self.stop_requested.clear()
            return {"ok": True, "action": "idle", "stopped": False, "cancel_requested": False}
        return {
            "ok": True,
            "action": "stopped",
            "stopped": stopped_playback or cancel_requested,
            "cancel_requested": cancel_requested,
            "previous_state": previous_state,
        }

    def generate_samples(
        self,
        text: str,
        voice_name: str,
        speed: float,
        lang: str,
    ) -> tuple[np.ndarray, int]:
        phonemes = self.kokoro.tokenizer.phonemize(text, lang)
        batched_phonemes = self.kokoro._split_phonemes(phonemes)
        if not batched_phonemes:
            raise ValueError("No phonemes generated")

        voice = self.kokoro.get_voice_style(voice_name)
        audio_parts = []
        sample_rate = 24000
        self._set_state("generating", batch=0, batches=len(batched_phonemes))

        for index, phoneme_batch in enumerate(batched_phonemes, start=1):
            if self.stop_requested.is_set():
                raise InterruptedError("Kokoro generation cancelled")
            self._set_state("generating", batch=index, batches=len(batched_phonemes))
            audio_part, sample_rate = self.kokoro._create_audio(phoneme_batch, voice, speed)
            if self.stop_requested.is_set():
                raise InterruptedError("Kokoro generation cancelled")
            audio_part, _ = trim_audio(audio_part)
            audio_parts.append(audio_part)

        if not audio_parts:
            raise InterruptedError("Kokoro generation cancelled")
        return np.concatenate(audio_parts), sample_rate

    def speak(self, text: str, voice: str | None, speed: float | None, lang: str | None) -> dict[str, Any]:
        if not self.generation_lock.acquire(blocking=False):
            result = self.stop()
            result["action"] = "stopped"
            return result

        text = text.strip()
        try:
            if self.is_busy():
                result = self.stop()
                result["action"] = "stopped"
                return result
            if not text:
                raise ValueError("Clipboard text is empty")

            config = self.reload_config()
            selected_voice = voice or str(config.get("voice", DEFAULT_CONFIG["voice"]))
            selected_speed = float(speed if speed is not None else config.get("speed", DEFAULT_CONFIG["speed"]))
            selected_lang = lang or str(config.get("lang", DEFAULT_CONFIG["lang"]))

            if selected_voice not in self.voices:
                raise ValueError(f"Unknown voice {selected_voice!r}. Run Kokoro Status to inspect available voices.")
            if selected_speed < 0.5 or selected_speed > 2.0:
                raise ValueError("Speed must be between 0.5 and 2.0")

            self.stop_requested.clear()
            self.stop_playback()
            self._set_state(
                "generating",
                chars=len(text),
                voice=selected_voice,
                speed=selected_speed,
                lang=selected_lang,
            )
            start = time.time()

            try:
                samples, sample_rate = self.generate_samples(text, selected_voice, selected_speed, selected_lang)
            except InterruptedError:
                self._set_state("idle")
                return {"ok": True, "action": "cancelled", "stopped": True}

            if self.stop_requested.is_set():
                self._set_state("idle")
                return {"ok": True, "action": "cancelled", "stopped": True}

            filename = f"kokoro-{int(time.time() * 1000)}.wav"
            audio_path = AUDIO_DIR / filename
            write_wav(audio_path, samples, sample_rate)
            elapsed = time.time() - start

            with self.playback_lock:
                self.playback_process = subprocess.Popen(
                    ["/usr/bin/afplay", str(audio_path)],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                playback_pid = self.playback_process.pid
                self.last_audio_path = audio_path
            self._set_state(
                "playing",
                chars=len(text),
                voice=selected_voice,
                speed=selected_speed,
                lang=selected_lang,
                batch=0,
                batches=0,
            )

            return {
                "ok": True,
                "action": "speaking",
                "voice": selected_voice,
                "speed": selected_speed,
                "lang": selected_lang,
                "chars": len(text),
                "sample_rate": sample_rate,
                "audio_path": str(audio_path),
                "playback_pid": playback_pid,
                "generation_seconds": round(elapsed, 3),
            }
        finally:
            self.generation_lock.release()

    def status(self) -> dict[str, Any]:
        playback_pid = None
        playback_running = False
        with self.playback_lock:
            if self.playback_process is not None:
                playback_pid = self.playback_process.pid
                playback_running = self.playback_process.poll() is None
                if not playback_running:
                    self.playback_process = None
                    with self.state_lock:
                        if self.state == "playing":
                            self._set_state("idle")

        with self.state_lock:
            state = self.state
            active_started_at = self.active_started_at
            active_elapsed = round(time.time() - active_started_at, 1) if active_started_at else None
            active_chars = self.active_chars
            active_voice = self.active_voice
            active_speed = self.active_speed
            active_lang = self.active_lang
            active_batch = self.active_batch
            active_batches = self.active_batches

        return {
            "ok": True,
            "pid": os.getpid(),
            "uptime_seconds": round(time.time() - self.started_at, 1),
            "model_variant": self.model_variant,
            "onnx_provider": ONNX_PROVIDER,
            "model_path": str(self.model_path),
            "voices_path": str(self.voices_path),
            "config_path": str(CONFIG_FILE),
            "cache_dir": str(CACHE_DIR),
            "state_dir": str(STATE_DIR),
            "voice": self.config.get("voice"),
            "speed": self.config.get("speed"),
            "lang": self.config.get("lang"),
            "state": state,
            "busy": state != "idle" or playback_running,
            "generation_running": state == "generating",
            "active_elapsed_seconds": active_elapsed,
            "active_chars": active_chars,
            "active_voice": active_voice,
            "active_speed": active_speed,
            "active_lang": active_lang,
            "active_batch": active_batch,
            "active_batches": active_batches,
            "cancel_requested": self.stop_requested.is_set(),
            "voices_count": len(self.voices),
            "voices": self.voices,
            "playback_running": playback_running,
            "playback_pid": playback_pid,
            "last_audio_path": str(self.last_audio_path) if self.last_audio_path else None,
        }


class ReusableThreadingHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


runtime: Runtime | None = None
server: ReusableThreadingHTTPServer | None = None
shutdown_requested = threading.Event()


class Handler(BaseHTTPRequestHandler):
    server_version = "KokoroClipboard/1.0"

    def log_message(self, format: str, *args: Any) -> None:
        logging.info("%s - %s", self.address_string(), format % args)

    def read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return {}
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def write_json(self, status: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        assert runtime is not None
        if self.path == "/status":
            self.write_json(200, runtime.status())
        elif self.path == "/voices":
            self.write_json(200, {"ok": True, "voices": runtime.voices})
        else:
            self.write_json(404, {"ok": False, "error": "Not found"})

    def do_POST(self) -> None:
        assert runtime is not None
        try:
            if self.path == "/speak":
                payload = self.read_json()
                result = runtime.speak(
                    text=str(payload.get("text", "")),
                    voice=payload.get("voice") or None,
                    speed=payload.get("speed"),
                    lang=payload.get("lang") or None,
                )
                self.write_json(200, result)
            elif self.path == "/stop":
                self.write_json(200, runtime.stop())
            elif self.path == "/config":
                payload = self.read_json()
                allowed = {key: payload[key] for key in ("voice", "speed", "lang") if key in payload}
                config = runtime.save_config_update(allowed)
                self.write_json(200, {"ok": True, "config": config})
            elif self.path == "/shutdown":
                runtime.stop()
                self.write_json(200, {"ok": True, "shutting_down": True})
                request_shutdown()
            else:
                self.write_json(404, {"ok": False, "error": "Not found"})
        except Exception as exc:
            logging.exception("Request failed")
            self.write_json(400, {"ok": False, "error": str(exc)})


def shutdown_server() -> None:
    time.sleep(0.1)
    if server is not None:
        server.shutdown()


def request_shutdown() -> None:
    if shutdown_requested.is_set():
        return
    shutdown_requested.set()
    threading.Thread(target=shutdown_server, daemon=True).start()


def write_pid_file() -> None:
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(f"{os.getpid()}\n", encoding="utf-8")


def cleanup() -> None:
    if runtime is not None:
        runtime.stop_playback()
    try:
        if PID_FILE.exists() and PID_FILE.read_text(encoding="utf-8").strip() == str(os.getpid()):
            PID_FILE.unlink()
    except OSError:
        pass


def handle_signal(signum: int, _frame: Any) -> None:
    logging.info("Received signal %s", signum)
    request_shutdown()


def main() -> int:
    global runtime, server
    configure_logging()
    ensure_dirs()
    write_pid_file()
    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    try:
        runtime = Runtime()
        server = ReusableThreadingHTTPServer((HOST, PORT), Handler)
        logging.info("Listening on http://%s:%s", HOST, PORT)
        server.serve_forever()
        return 0
    finally:
        if server is not None:
            server.server_close()
        cleanup()
        logging.info("Stopped")


if __name__ == "__main__":
    raise SystemExit(main())

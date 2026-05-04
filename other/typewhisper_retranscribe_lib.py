from __future__ import annotations

import json
import os
import sqlite3
import subprocess
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path


APP_SUPPORT_DIR = Path.home() / "Library/Application Support/TypeWhisper"
HISTORY_DB_PATH = APP_SUPPORT_DIR / "history.store"
AUDIO_DIR = APP_SUPPORT_DIR / "audio"
GROQ_TRANSCRIPTIONS_URL = "https://api.groq.com/openai/v1/audio/transcriptions"
GROQ_MODEL = "whisper-large-v3"
APPLE_REFERENCE_DATE = datetime(2001, 1, 1, tzinfo=timezone.utc)
UTF8_ENV = {
    **os.environ,
    "LANG": "en_US.UTF-8",
    "LC_ALL": "en_US.UTF-8",
}


@dataclass(frozen=True)
class HistoryEntry:
    final_text: str
    audio_path: Path
    duration_seconds: float
    timestamp: datetime

    @property
    def chooser_label(self) -> str:
        return f"{self.timestamp.strftime('%Y-%m-%d %H:%M')} | {format_duration(self.duration_seconds)} | {clip_text(self.final_text, 96)}"


def clip_text(text: str, limit: int) -> str:
    condensed = " ".join(text.split())
    if len(condensed) <= limit:
        return condensed
    return condensed[: limit - 1] + "…"


def format_duration(duration_seconds: float) -> str:
    total_seconds = max(0, int(round(duration_seconds)))
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)

    if hours:
        return f"{hours}h {minutes:02d}m {seconds:02d}s"
    if minutes:
        return f"{minutes}m {seconds:02d}s"
    return f"{seconds}s"


def load_recent_audio_entries(limit: int = 10) -> list[HistoryEntry]:
    if not HISTORY_DB_PATH.exists():
        raise RuntimeError(f"TypeWhisper history database not found at {HISTORY_DB_PATH}")
    if not AUDIO_DIR.exists():
        raise RuntimeError(f"TypeWhisper audio directory not found at {AUDIO_DIR}")

    entries: list[HistoryEntry] = []
    with sqlite3.connect(f"file:{HISTORY_DB_PATH}?mode=ro", uri=True) as connection:
        rows = connection.execute(
            """
            SELECT
                COALESCE(ZFINALTEXT, ''),
                ZAUDIOFILENAME,
                COALESCE(ZDURATIONSECONDS, 0),
                COALESCE(ZTIMESTAMP, 0)
            FROM ZTRANSCRIPTIONRECORD
            WHERE COALESCE(ZAUDIOFILENAME, '') != ''
            ORDER BY ZTIMESTAMP DESC
            """,
        ).fetchall()

    for final_text, audio_file_name, duration_seconds, timestamp_seconds in rows:
        audio_path = AUDIO_DIR / audio_file_name
        if not audio_path.exists():
            continue

        timestamp = APPLE_REFERENCE_DATE + timedelta(seconds=float(timestamp_seconds))
        entries.append(
            HistoryEntry(
                final_text=final_text,
                audio_path=audio_path,
                duration_seconds=float(duration_seconds),
                timestamp=timestamp.astimezone(),
            )
        )
        if len(entries) >= limit:
            break

    if not entries:
        raise RuntimeError(
            "No saved TypeWhisper WAV files found. Enable 'Save audio with transcriptions' in TypeWhisper first."
        )

    return entries


def transcribe_audio(audio_path: Path) -> str:
    if not audio_path.exists():
        raise RuntimeError(f"Audio file not found: {audio_path}")

    result = subprocess.run(
        [
            "curl",
            "--silent",
            "--show-error",
            "--fail-with-body",
            "--max-time",
            "120",
            GROQ_TRANSCRIPTIONS_URL,
            "-H",
            f"Authorization: Bearer {load_groq_api_key()}",
            "-F",
            f"file=@{audio_path};type=audio/wav",
            "-F",
            f"model={GROQ_MODEL}",
            "-F",
            "response_format=json",
            "-F",
            "temperature=0",
        ],
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
        env=UTF8_ENV,
    )
    if result.returncode != 0:
        details = (result.stderr or result.stdout).strip()
        raise RuntimeError(f"Groq transcription failed: {details}")

    try:
        response_payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Groq returned invalid JSON: {result.stdout}") from exc

    text = response_payload.get("text", "").strip() if isinstance(response_payload, dict) else ""

    if not text:
        raise RuntimeError("Groq returned empty transcription text")

    return text


def load_groq_api_key() -> str:
    for secrets_path in candidate_secrets_paths():
        if api_key := source_groq_api_key(secrets_path):
            return api_key

    if api_key := os.environ.get("GROQ_API_KEY"):
        return api_key

    raise RuntimeError("GROQ_API_KEY is not set and no Groq key was found in .secrets")


def candidate_secrets_paths() -> list[Path]:
    seen: set[Path] = set()
    paths: list[Path] = []

    for start in [Path.home(), Path(__file__).resolve().parent, Path.cwd()]:
        for directory in [start, *start.parents]:
            path = directory / ".secrets"
            if path in seen:
                continue
            seen.add(path)
            if path.exists():
                paths.append(path)

    return paths


def source_groq_api_key(path: Path) -> str | None:
    result = subprocess.run(
        [
            "/bin/zsh",
            "-lc",
            'unset GROQ_API_KEY; source "$1" >/dev/null; printf "%s" "${GROQ_API_KEY:-}"',
            "typewhisper-secrets",
            str(path),
        ],
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
        env=UTF8_ENV,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to source Groq key from {path}: {result.stderr.strip()}")

    api_key = result.stdout.strip()
    return api_key or None


def copy_to_clipboard(text: str) -> None:
    result = subprocess.run(
        ["pbcopy"],
        input=text,
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
        env=UTF8_ENV,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Failed to copy transcription to clipboard")


def paste_clipboard() -> None:
    applescript = """
delay 0.35
tell application "System Events"
    keystroke "v" using command down
end tell
"""
    result = subprocess.run(
        ["osascript"],
        input=applescript,
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
        env=UTF8_ENV,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Copied transcription, but automatic paste failed")


def choose_entry(entries: list[HistoryEntry]) -> HistoryEntry | None:
    labels = [f"{index + 1}. {entry.chooser_label}" for index, entry in enumerate(entries)]
    script = """
on run argv
    if (count of argv) is 0 then return ""
    set chosen to choose from list argv with title "TypeWhisper Retranscribe" with prompt "Pick a recent saved dictation WAV to retranscribe:" OK button name "Retranscribe"
    if chosen is false then return ""
    return item 1 of chosen
end run
"""
    result = subprocess.run(
        ["osascript", "-e", script, *labels],
        text=True,
        encoding="utf-8",
        capture_output=True,
        check=False,
        env=UTF8_ENV,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Failed to show chooser")

    selection = result.stdout.strip()
    if not selection:
        return None

    prefix, _, _ = selection.partition(". ")
    try:
        selected_index = int(prefix) - 1
    except ValueError as exc:
        raise RuntimeError("Could not decode the selected transcription entry") from exc

    if 0 <= selected_index < len(entries):
        return entries[selected_index]

    raise RuntimeError("Selected transcription entry is out of range")

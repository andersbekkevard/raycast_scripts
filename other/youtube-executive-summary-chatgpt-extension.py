#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "youtube-transcript-api>=1.2.4",
# ]
# ///

from __future__ import annotations

import importlib.util
import json
import secrets
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import ModuleType
from urllib.parse import parse_qs, urlencode, urlparse


PROMPT_PREFIX = "Give the executive summary of the following YouTube video:"
CHATGPT_URL = "https://chatgpt.com/"
TERMINAL_STATES = {"conversation_created", "failed"}


def run_command(args: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        input=input_text,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )


def load_transcript_module() -> ModuleType:
    module_path = Path(__file__).with_name("youtube-transcript-clipboard.py")
    spec = importlib.util.spec_from_file_location("youtube_transcript_clipboard", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load transcript helper: {module_path}")

    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def active_browser_url() -> str:
    script = r'''
tell application "System Events"
    if not (exists process "Google Chrome") then return ""
end tell

tell application "Google Chrome"
    if (count of windows) is 0 then return ""
    try
        return URL of active tab of window 1
    on error
        return ""
    end try
end tell
'''
    result = run_command(["osascript"], input_text=script)
    return result.stdout.strip() if result.returncode == 0 else ""


def resolve_source(transcript_module: ModuleType) -> tuple[str, str]:
    active_url = active_browser_url()
    if active_url:
        try:
            transcript_module.extract_video_id(active_url)
        except ValueError:
            pass
        else:
            return active_url, "active Chrome tab"

    clipboard_value = transcript_module.read_clipboard()
    if clipboard_value:
        try:
            transcript_module.extract_video_id(clipboard_value)
        except ValueError:
            pass
        else:
            return clipboard_value, "clipboard"

    raise ValueError("Neither the active Chrome tab nor the clipboard contains a supported YouTube URL.")


def fetch_prompt(transcript_module: ModuleType, source: str) -> tuple[str, str]:
    video_id = transcript_module.extract_video_id(source)
    choice = transcript_module.choose_transcript(video_id)
    fetched = choice.transcript.fetch()
    transcript = transcript_module.format_transcript_text(list(fetched))

    language_note = choice.transcript.language_code
    if not choice.used_preferred_language:
        language_note = f"{language_note} (first available)"
    return f"{PROMPT_PREFIX}\n\n{transcript}", language_note


@dataclass
class RunState:
    token: str
    started_at: float
    prompt: str | None = None
    language_note: str | None = None
    fetch_error: str | None = None
    events: list[dict[str, object]] = field(default_factory=list)
    condition: threading.Condition = field(default_factory=threading.Condition)

    def elapsed_ms(self) -> int:
        return round((time.perf_counter() - self.started_at) * 1000)

    def record(self, event: dict[str, object]) -> None:
        with self.condition:
            self.events.append({"bridge_elapsed_ms": self.elapsed_ms(), **event})
            self.condition.notify_all()

    def wait_for_terminal(self, timeout: float) -> dict[str, object]:
        deadline = time.monotonic() + timeout
        with self.condition:
            while True:
                for event in reversed(self.events):
                    if event.get("state") in TERMINAL_STATES:
                        return event
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("Timed out waiting for the ChatGPT extension.")
                self.condition.wait(remaining)


def handler_for(state: RunState) -> type[BaseHTTPRequestHandler]:
    class BridgeHandler(BaseHTTPRequestHandler):
        def log_message(self, _format: str, *_args: object) -> None:
            return

        def send_json(self, status: int, payload: dict[str, object]) -> None:
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def authorized(self) -> bool:
            query = parse_qs(urlparse(self.path).query)
            return secrets.compare_digest(query.get("token", [""])[0], state.token)

        def do_GET(self) -> None:  # noqa: N802
            if not self.authorized():
                self.send_json(403, {"error": "Invalid bridge token."})
                return
            if urlparse(self.path).path != "/payload":
                self.send_json(404, {"error": "Unknown bridge endpoint."})
                return
            with state.condition:
                if state.fetch_error:
                    self.send_json(500, {"error": state.fetch_error})
                elif state.prompt is None:
                    self.send_json(202, {"state": "pending"})
                else:
                    self.send_json(200, {"prompt": state.prompt})

        def do_POST(self) -> None:  # noqa: N802
            if not self.authorized():
                self.send_json(403, {"error": "Invalid bridge token."})
                return
            if urlparse(self.path).path != "/status":
                self.send_json(404, {"error": "Unknown bridge endpoint."})
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                event = json.loads(self.rfile.read(length))
                if not isinstance(event, dict) or not isinstance(event.get("state"), str):
                    raise ValueError("Invalid status payload.")
            except (ValueError, json.JSONDecodeError) as exc:
                self.send_json(400, {"error": str(exc)})
                return
            state.record(event)
            self.send_json(200, {"ok": True})

    return BridgeHandler


def open_chatgpt(port: int, token: str, *, replace_video_id: str | None) -> None:
    query = urlencode({"yt_summary_run": token, "yt_summary_port": port})
    url = f"{CHATGPT_URL}?{query}"
    expected_video_id = replace_video_id or ""
    script = rf'''
tell application "Google Chrome"
    activate
    if (count of windows) is 0 then make new window
    set frontWindow to window 1
    set replacedYouTubeTab to false

    if "{expected_video_id}" is not "" then
        try
            if URL of active tab of frontWindow contains "{expected_video_id}" then
                set URL of active tab of frontWindow to "{url}"
                set replacedYouTubeTab to true
            end if
        end try
    end if

    if replacedYouTubeTab is false then
        set tabCount to count of tabs of frontWindow
        make new tab at end of tabs of frontWindow with properties {{URL:"{url}"}}
        set active tab index of frontWindow to (tabCount + 1)
    end if
end tell
'''
    result = run_command(["osascript"], input_text=script)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Failed to open ChatGPT in Chrome.")


def main() -> int:
    started_at = time.perf_counter()
    try:
        transcript_module = load_transcript_module()
        source, source_label = resolve_source(transcript_module)
        state = RunState(token=secrets.token_urlsafe(24), started_at=started_at)
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler_for(state))
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()

        def fetch() -> None:
            try:
                prompt, language_note = fetch_prompt(transcript_module, source)
                with state.condition:
                    state.prompt = prompt
                    state.language_note = language_note
                    state.events.append({"state": "transcript_ready", "bridge_elapsed_ms": state.elapsed_ms()})
                    state.condition.notify_all()
            except Exception as exc:  # The main thread reports the friendly version.
                with state.condition:
                    state.fetch_error = transcript_module.friendly_error(exc)
                    state.condition.notify_all()

        fetch_thread = threading.Thread(target=fetch, daemon=True)
        fetch_thread.start()
        replace_video_id = (
            transcript_module.extract_video_id(source)
            if source_label == "active Chrome tab"
            else None
        )
        open_chatgpt(server.server_port, state.token, replace_video_id=replace_video_id)
        terminal = state.wait_for_terminal(45)

        if terminal.get("state") == "failed":
            raise RuntimeError(str(terminal.get("error") or "The ChatGPT extension failed."))
        if state.fetch_error:
            raise RuntimeError(state.fetch_error)

    except Exception as exc:
        try:
            message = transcript_module.friendly_error(exc)
        except UnboundLocalError:
            message = str(exc).strip() or "Failed to summarize the YouTube video."
        print(message, file=sys.stderr)
        return 1

    elapsed = (time.perf_counter() - started_at) * 1000
    print(
        f"Submitted transcript from {source_label} to ChatGPT "
        f"({state.language_note}) in {elapsed / 1000:.2f}s."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

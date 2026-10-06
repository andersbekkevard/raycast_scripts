#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "youtube-transcript-api>=1.2.4",
# ]
# ///

import importlib.util
import subprocess
import time
import sys
from pathlib import Path
from types import ModuleType


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'lib'))
import browser_control

SELECTED_BROWSER = None


PROMPT_PREFIX = "Give the executive summary of the following YouTube video:"
CHATGPT_URL = "https://chatgpt.com/"


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
    global SELECTED_BROWSER
    cfg, ctx = browser_control.config(), browser_control.context()
    windows = browser_control.inventory(cfg, ctx)
    SELECTED_BROWSER = browser_control.select_browser(cfg, windows, ctx['front'])
    if not windows.get(SELECTED_BROWSER):
        return ""
    return browser_control.active(cfg, ctx, windows)['url']


def resolve_source(transcript_module: ModuleType) -> tuple[str, str]:
    active_url = active_browser_url()
    if active_url:
        try:
            transcript_module.extract_video_id(active_url)
        except ValueError:
            pass
        else:
            return active_url, "active browser tab"

    clipboard_value = transcript_module.read_clipboard()
    if clipboard_value:
        try:
            transcript_module.extract_video_id(clipboard_value)
        except ValueError:
            pass
        else:
            return clipboard_value, "clipboard"

    raise ValueError("Neither the active browser tab nor the clipboard contains a supported YouTube URL.")


def fetch_transcript(transcript_module: ModuleType, source: str) -> tuple[str, str]:
    video_id = transcript_module.extract_video_id(source)
    choice = transcript_module.choose_transcript(video_id)
    fetched = choice.transcript.fetch()
    text = transcript_module.format_transcript_text(list(fetched))

    language_note = choice.transcript.language_code
    if not choice.used_preferred_language:
        language_note = f"{language_note} (first available)"
    return text, language_note


def open_chatgpt_and_submit(prompt: str) -> None:
    browser = SELECTED_BROWSER or browser_control.config()['default_browser']
    browser_control.bridge(browser, 'open', {'url': CHATGPT_URL})
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        if browser_control.bridge(browser, 'ready'):
            break
        time.sleep(0.1)
    if browser == 'Safari':
        time.sleep(2)
    clipboard_result = run_command(["pbcopy"], input_text=prompt)
    if clipboard_result.returncode != 0:
        raise RuntimeError(clipboard_result.stderr.strip() or "Failed to copy the prompt.")

    submit_script = r'''
tell application "Google Chrome" to activate
delay 0.3
tell application "System Events"
    key code 53
    delay 0.1
    keystroke "g"
    keystroke "i"
    delay 0.3
    key code 9 using {command down}
end tell

repeat 30 times
    tell application "Google Chrome"
        try
            if URL of active tab of window 1 contains "chatgpt.com/c/" then return "submitted"
        end try
    end tell
    tell application "System Events" to key code 36
    delay 0.5
end repeat
return "not-submitted"
'''
    submit_script = submit_script.replace('"Google Chrome"', '"' + browser + '"')
    if browser == 'Safari':
        submit_script = submit_script.replace('active tab', 'current tab')
    result = run_command(["osascript"], input_text=submit_script)
    if result.returncode != 0:
        raise RuntimeError(
            result.stderr.strip()
            or "Opened ChatGPT and copied the prompt, but automatic submission failed."
        )
    if result.stdout.strip() != "submitted":
        raise RuntimeError("The prompt was pasted, but ChatGPT did not confirm submission.")


def main() -> int:
    try:
        transcript_module = load_transcript_module()
        source, source_label = resolve_source(transcript_module)
        transcript, language_note = fetch_transcript(transcript_module, source)
        prompt = f"{PROMPT_PREFIX}\n\n{transcript}"
        open_chatgpt_and_submit(prompt)
    except Exception as exc:
        try:
            message = transcript_module.friendly_error(exc)
        except UnboundLocalError:
            message = str(exc).strip() or "Failed to summarize the YouTube video."
        print(message, file=sys.stderr)
        return 1

    print(f"Sent transcript from {source_label} to ChatGPT ({language_note}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

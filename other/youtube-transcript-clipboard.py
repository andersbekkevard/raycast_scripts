#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "youtube-transcript-api>=1.2.4",
# ]
# ///

import argparse
import html
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from urllib.parse import parse_qs, urlparse

from youtube_transcript_api import YouTubeTranscriptApi


VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
NON_VERBAL_MARKERS = {
    "[music]",
    "[applause]",
    "[laughter]",
    "[cheering]",
}


@dataclass(frozen=True)
class TranscriptChoice:
    transcript: object
    used_preferred_language: bool


def run_command(args: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
    )


def read_clipboard() -> str:
    result = run_command(["pbpaste"])
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Failed to read the clipboard.")
    return result.stdout.strip()


def write_clipboard(text: str) -> None:
    result = run_command(["pbcopy"], input_text=text)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Failed to write the transcript to the clipboard.")


def paste_clipboard() -> None:
    applescript = """
delay 0.35
tell application "System Events"
    keystroke "v" using command down
end tell
"""
    result = run_command(["osascript"], input_text=applescript)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "Copied the transcript, but automatic paste failed.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch a YouTube transcript from a URL in the clipboard and paste it."
    )
    parser.add_argument(
        "url",
        nargs="?",
        help="Optional YouTube URL or video ID. If omitted, the script reads from the clipboard.",
    )
    parser.add_argument(
        "--no-paste",
        action="store_true",
        help="Copy the transcript to the clipboard without simulating Cmd+V.",
    )
    return parser.parse_args()


def extract_video_id(value: str) -> str:
    candidate = value.strip()
    if not candidate:
        raise ValueError("Clipboard is empty.")

    if VIDEO_ID_RE.fullmatch(candidate):
        return candidate

    parsed = urlparse(candidate)
    host = parsed.netloc.lower()
    path_parts = [part for part in parsed.path.split("/") if part]

    if host in {"youtu.be", "www.youtu.be"}:
        if path_parts and VIDEO_ID_RE.fullmatch(path_parts[0]):
            return path_parts[0]

    youtube_hosts = {
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com",
    }
    if host in youtube_hosts:
        if parsed.path == "/watch":
            video_id = parse_qs(parsed.query).get("v", [""])[0]
            if VIDEO_ID_RE.fullmatch(video_id):
                return video_id

        for prefix in ("shorts", "embed", "live", "v"):
            if len(path_parts) >= 2 and path_parts[0] == prefix and VIDEO_ID_RE.fullmatch(path_parts[1]):
                return path_parts[1]

    raise ValueError("Clipboard does not contain a supported YouTube URL or video ID.")


def preferred_language_codes() -> list[str]:
    codes: list[str] = []
    for env_name in ("LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"):
        raw_value = os.getenv(env_name, "")
        if not raw_value:
            continue

        for item in raw_value.split(":"):
            item = item.split(".", 1)[0].strip()
            if not item:
                continue

            normalized = item.replace("_", "-").lower()
            if normalized not in codes:
                codes.append(normalized)

            base = normalized.split("-", 1)[0]
            if base and base not in codes:
                codes.append(base)

    for fallback in ("en",):
        if fallback not in codes:
            codes.append(fallback)
    return codes


def matches_language(language_code: str, preferred_codes: list[str]) -> bool:
    normalized = language_code.lower()
    base = normalized.split("-", 1)[0]
    return normalized in preferred_codes or base in preferred_codes


def choose_transcript(video_id: str) -> TranscriptChoice:
    api = YouTubeTranscriptApi()
    transcripts = list(api.list(video_id))
    if not transcripts:
        raise RuntimeError("No transcripts are available for this video.")

    preferred_codes = preferred_language_codes()

    for prefer_generated in (False, True):
        for transcript in transcripts:
            if transcript.is_generated != prefer_generated:
                continue
            if matches_language(transcript.language_code, preferred_codes):
                return TranscriptChoice(transcript=transcript, used_preferred_language=True)

    for prefer_generated in (False, True):
        for transcript in transcripts:
            if transcript.is_generated == prefer_generated:
                return TranscriptChoice(transcript=transcript, used_preferred_language=False)

    raise RuntimeError("No usable transcript was found.")


def clean_snippet_text(text: str) -> str:
    normalized = " ".join(html.unescape(text).replace("\xa0", " ").split())
    if normalized.lower() in NON_VERBAL_MARKERS:
        return ""
    return normalized


def format_transcript_text(snippets: list[object]) -> str:
    paragraphs: list[str] = []
    current_parts: list[str] = []
    current_length = 0

    for snippet in snippets:
        text = clean_snippet_text(getattr(snippet, "text", ""))
        if not text:
            continue

        current_parts.append(text)
        current_length += len(text) + 1

        if current_length >= 700 and text.endswith((".", "?", "!", ":", "…")):
            paragraphs.append(" ".join(current_parts))
            current_parts = []
            current_length = 0

    if current_parts:
        paragraphs.append(" ".join(current_parts))

    transcript_text = "\n\n".join(paragraphs).strip()
    if not transcript_text:
        raise RuntimeError("Transcript was retrieved, but it did not contain any text.")
    return transcript_text


def friendly_error(exc: Exception) -> str:
    error_name = exc.__class__.__name__
    error_message = str(exc).strip()

    custom_messages = {
        "NoTranscriptFound": "No transcript was found for this video.",
        "TranscriptsDisabled": "This video does not expose transcripts.",
        "VideoUnavailable": "This video is unavailable.",
        "RequestBlocked": "YouTube blocked the transcript request from this machine.",
        "IpBlocked": "YouTube blocked transcript requests from this IP address.",
        "TooManyRequests": "YouTube is rate-limiting transcript requests right now.",
    }

    if error_name in custom_messages:
        return custom_messages[error_name]
    if error_message:
        return error_message
    return "Failed to fetch the YouTube transcript."


def main() -> int:
    args = parse_args()

    try:
        source = args.url or read_clipboard()
        video_id = extract_video_id(source)
        choice = choose_transcript(video_id)
        fetched = choice.transcript.fetch()
        transcript_text = format_transcript_text(list(fetched))
        write_clipboard(transcript_text)
        if not args.no_paste:
            paste_clipboard()
    except Exception as exc:
        print(friendly_error(exc), file=sys.stderr)
        return 1

    language_note = choice.transcript.language_code
    if not choice.used_preferred_language:
        language_note = f"{language_note} (first available)"

    if args.no_paste:
        print(f"Transcript copied to clipboard from {language_note}.")
    else:
        print(f"Transcript copied to clipboard and pasted from {language_note}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# YouTube Executive Summary Bridge

This unpacked Chromium extension owns only the ChatGPT page interaction. The
Raycast command fetches the transcript and exposes it through a token-protected,
loopback-only, one-shot bridge.

Load this directory from `comet://extensions` with **Developer mode → Load
unpacked**. The existing `Summarize YouTube in ChatGPT` Raycast command remains
the single user-facing interface.

The extension does nothing on ordinary ChatGPT tabs. It activates only when the
local command opens a URL containing a fresh `yt_summary_run` token.

When the active Comet tab supplied the YouTube URL, the command replaces that
tab with ChatGPT. Clipboard fallback opens ChatGPT in a new tab so an unrelated
active tab is never closed.

#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Codex Sessions Euphony
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🧠

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Launch a local searchable Codex sessions UI plus local Euphony viewer

set -euo pipefail

export PATH="$HOME/Library/pnpm:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="${CODEX_SESSIONS_ROOT:-$HOME/.codex/sessions}"
EUPHONY_DIR="${CODEX_EUPHONY_DIR:-/Users/andersbekkevard/dev/external/euphony}"
INDEX_PORT="${CODEX_SESSIONS_PORT:-8765}"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/raycast-codex-sessions-euphony"
INDEX_SERVER_SCRIPT="$CACHE_DIR/codex_sessions_index.py"
INDEX_LOG="$CACHE_DIR/index.log"
FRONTEND_STAMP="$CACHE_DIR/frontend-install.stamp"
BUILD_STAMP="$CACHE_DIR/frontend-build.stamp"
INDEX_LAUNCH_LABEL="ai.codex.sessions.euphony"

mkdir -p "$CACHE_DIR"

notify() {
  local message="$1"
  local escaped_message="${message//\\/\\\\}"
  escaped_message="${escaped_message//\"/\\\"}"
  osascript -e "display notification \"$escaped_message\" with title \"Codex Sessions Euphony\"" >/dev/null 2>&1 || true
}

fail() {
  local message="$1"
  echo "$message" >&2
  notify "$message"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 80); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

ensure_euphony_repo() {
  if [[ -d "$EUPHONY_DIR/.git" ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$EUPHONY_DIR")"
  git clone https://github.com/openai/euphony "$EUPHONY_DIR" >/dev/null 2>&1 || \
    fail "Failed to clone Euphony into $EUPHONY_DIR"
}

ensure_frontend_patch() {
  local target="$EUPHONY_DIR/src/utils/api-manager.ts"
  [[ -f "$target" ]] || return 0

  if rg -q 'const FRONTEND_ONLY_MODE_MAX_LINES = 100;' "$target"; then
    perl -0pi -e 's/const FRONTEND_ONLY_MODE_MAX_LINES = 100;/const FRONTEND_ONLY_MODE_MAX_LINES = 200000;/' "$target"
  fi
}

ensure_frontend_deps() {
  local lockfile="$EUPHONY_DIR/pnpm-lock.yaml"
  if [[ ! -d "$EUPHONY_DIR/node_modules" || ! -f "$FRONTEND_STAMP" || "$lockfile" -nt "$FRONTEND_STAMP" || "$EUPHONY_DIR/package.json" -nt "$FRONTEND_STAMP" ]]; then
    (cd "$EUPHONY_DIR" && pnpm install) >/tmp/codex-sessions-euphony-pnpm.log 2>&1 || \
      fail "pnpm install failed. See /tmp/codex-sessions-euphony-pnpm.log"
    touch "$FRONTEND_STAMP"
  fi
}

ensure_frontend_build() {
  local dist_index="$EUPHONY_DIR/dist/index.html"
  local needs_build="0"

  if [[ ! -f "$dist_index" || ! -f "$BUILD_STAMP" ]]; then
    needs_build="1"
  elif find "$EUPHONY_DIR/src" -type f -newer "$BUILD_STAMP" | grep -q .; then
    needs_build="1"
  elif [[ "$EUPHONY_DIR/index.html" -nt "$BUILD_STAMP" || "$EUPHONY_DIR/package.json" -nt "$BUILD_STAMP" || "$EUPHONY_DIR/vite.config.ts" -nt "$BUILD_STAMP" ]]; then
    needs_build="1"
  fi

  if [[ "$needs_build" == "1" ]]; then
    (cd "$EUPHONY_DIR" && VITE_EUPHONY_FRONTEND_ONLY=true pnpm run build) >/tmp/codex-sessions-euphony-build.log 2>&1 || \
      fail "Euphony frontend build failed. See /tmp/codex-sessions-euphony-build.log"
    touch "$BUILD_STAMP"
  fi
}

write_index_server() {
  cat >"$INDEX_SERVER_SCRIPT" <<'PY'
from __future__ import annotations

import json
import os
from collections import deque
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

ROOT = Path(os.environ.get("CODEX_SESSIONS_ROOT", str(Path.home() / ".codex" / "sessions"))).expanduser().resolve()
EUPHONY_DIST = Path(os.environ["EUPHONY_DIST"]).resolve()
PORT = int(os.environ.get("PORT", "8765"))


def clip(text: str, limit: int = 180) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "..."


def extract_text(value) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return " ".join(part for item in value if (part := extract_text(item)))
    if isinstance(value, dict):
        parts: list[str] = []
        if isinstance(value.get("text"), str):
            parts.append(value["text"])
        if "content" in value:
            parts.append(extract_text(value["content"]))
        if "parts" in value:
            parts.append(extract_text(value["parts"]))
        return " ".join(part for part in parts if part)
    return ""


def resolve_euphony_path(path_fragment: str) -> Path:
    candidate = (EUPHONY_DIST / path_fragment.lstrip("/")).resolve()
    try:
        candidate.relative_to(EUPHONY_DIST)
    except ValueError:
        raise FileNotFoundError(path_fragment)
    return candidate


def parse_session(path: Path) -> dict[str, object]:
    cwd = ""
    started = ""
    users: deque[str] = deque(maxlen=3)
    assistants: deque[str] = deque(maxlen=2)

    try:
        handle = path.open()
    except OSError:
        return {}

    with handle:
        for line in handle:
            try:
                obj = json.loads(line)
            except Exception:
                continue

            payload = obj.get("payload") or {}
            event_type = obj.get("type")

            if event_type == "session_meta":
                cwd = payload.get("cwd") or cwd
                started = payload.get("timestamp") or started
                continue

            if event_type != "response_item":
                continue
            if payload.get("type") != "message":
                continue

            role = payload.get("role")
            text = clip(extract_text(payload.get("content", [])), 260)
            if not text:
                continue

            if role == "user":
                users.append(text)
            elif role == "assistant":
                assistants.append(text)

    stat = path.stat()
    return {
        "path": str(path),
        "cwd": cwd,
        "started": started,
        "mtime": int(stat.st_mtime),
        "size": stat.st_size,
        "users": list(users),
        "assistants": list(assistants),
    }


def list_sessions() -> list[dict[str, object]]:
    records = []
    for path in ROOT.rglob("*.jsonl"):
        rec = parse_session(path)
        if not rec:
            continue
        rec["rel"] = path.relative_to(ROOT).as_posix()
        records.append(rec)
    records.sort(key=lambda item: (item.get("started") or "", item["path"]), reverse=True)
    return records


INDEX_HTML = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>Codex Sessions</title>
<style>
:root {
  --bg: #0f1111;
  --panel: #171918;
  --panel-2: #1d201f;
  --line: #2b2f2d;
  --text: #f3f1ea;
  --muted: #a59c8d;
  --accent: #6ecb8b;
  --accent-2: #4aa3df;
  --accent-3: #f2b561;
  --danger: #ff8d80;
  --shadow: rgba(0, 0, 0, 0.22);
  --mono: ui-monospace, SFMono-Regular, Menlo, monospace;
}
* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  color: var(--text);
  font: 14px/1.45 ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background:
    radial-gradient(circle at top left, rgba(110, 203, 139, 0.12), transparent 26rem),
    radial-gradient(circle at top right, rgba(74, 163, 223, 0.12), transparent 26rem),
    linear-gradient(180deg, #111313, var(--bg));
}
.app {
  display: grid;
  grid-template-rows: auto 1fr;
  height: 100%;
}
.header {
  padding: 20px 22px 14px;
  border-bottom: 1px solid var(--line);
  background: rgba(15, 17, 17, 0.86);
  backdrop-filter: blur(10px);
}
.title {
  margin: 0 0 6px;
  font-size: 26px;
  font-weight: 700;
}
.subtitle {
  margin: 0;
  color: var(--muted);
}
.searchbar {
  display: grid;
  grid-template-columns: 1fr auto auto;
  gap: 12px;
  margin-top: 16px;
}
.searchbar input {
  width: 100%;
  border: 1px solid var(--line);
  border-radius: 14px;
  background: var(--panel);
  color: var(--text);
  padding: 14px 16px;
  font: inherit;
}
.searchbar button {
  border: 0;
  border-radius: 12px;
  padding: 12px 14px;
  cursor: pointer;
  font: inherit;
  color: white;
  background: var(--accent-2);
}
.main {
  display: grid;
  grid-template-columns: minmax(420px, 58%) minmax(320px, 42%);
  min-height: 0;
}
.results {
  border-right: 1px solid var(--line);
  min-height: 0;
  overflow: auto;
}
.preview {
  min-height: 0;
  overflow: auto;
  background: rgba(255,255,255,0.01);
}
.summary {
  padding: 12px 18px;
  color: var(--muted);
  border-bottom: 1px solid var(--line);
}
.item {
  padding: 14px 18px 15px;
  border-bottom: 1px solid rgba(255,255,255,0.04);
  cursor: pointer;
}
.item.active {
  background: linear-gradient(90deg, rgba(110, 203, 139, 0.12), rgba(74, 163, 223, 0.05));
}
.item-top {
  display: flex;
  justify-content: space-between;
  gap: 10px;
  margin-bottom: 6px;
}
.item-date {
  color: var(--accent-3);
  font: 12px/1.3 var(--mono);
}
.item-rel {
  color: var(--muted);
  font: 12px/1.3 var(--mono);
  word-break: break-all;
}
.item-cwd {
  margin: 0 0 6px;
  color: var(--accent);
  font: 13px/1.35 var(--mono);
  word-break: break-all;
}
.item-user, .item-assistant {
  margin: 0;
  color: var(--text);
}
.item-assistant {
  color: #d4d0c8;
  margin-top: 4px;
}
.item-label {
  color: var(--muted);
}
.preview-inner {
  padding: 20px 20px 28px;
}
.preview-heading {
  margin: 0 0 10px;
  font-size: 20px;
}
.meta-grid {
  display: grid;
  gap: 8px;
  margin-bottom: 18px;
}
.meta-row {
  display: grid;
  gap: 4px;
}
.meta-label {
  color: var(--muted);
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}
.meta-value {
  font: 13px/1.4 var(--mono);
  word-break: break-all;
}
.actions {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
  margin-bottom: 18px;
}
.actions button, .actions a {
  border: 0;
  border-radius: 999px;
  padding: 10px 13px;
  cursor: pointer;
  text-decoration: none;
  font: inherit;
  color: white;
  background: var(--accent);
}
.actions .secondary {
  background: var(--accent-2);
}
.actions .tertiary {
  background: #3b3f3d;
}
.section-title {
  margin: 18px 0 8px;
  color: var(--muted);
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
}
.message-list {
  display: grid;
  gap: 8px;
}
.message {
  border: 1px solid var(--line);
  border-radius: 12px;
  padding: 10px 12px;
  background: var(--panel);
}
.message.user { border-left: 3px solid var(--accent-3); }
.message.assistant { border-left: 3px solid var(--accent-2); }
.placeholder {
  color: var(--muted);
  padding: 24px 20px;
}
.toast {
  position: fixed;
  right: 16px;
  bottom: 16px;
  background: #1e1b18;
  color: white;
  padding: 10px 12px;
  border-radius: 10px;
  opacity: 0;
  transform: translateY(8px);
  transition: opacity 0.18s ease, transform 0.18s ease;
}
.toast.show {
  opacity: 1;
  transform: translateY(0);
}
@media (max-width: 980px) {
  .main { grid-template-columns: 1fr; }
  .results { border-right: 0; border-bottom: 1px solid var(--line); max-height: 45vh; }
}
</style>
</head>
<body>
<div class="app">
  <div class="header">
    <h1 class="title">Codex Sessions</h1>
    <p class="subtitle">Search by cwd, path, or recent messages. Arrow keys move, Enter opens the selected log in local Euphony.</p>
    <div class="searchbar">
      <input id="query" placeholder="Search sessions..." autofocus />
      <button id="clear">Clear</button>
      <button id="openRoot">Open Euphony</button>
    </div>
  </div>
  <div class="main">
    <div class="results">
      <div id="summary" class="summary"></div>
      <div id="list"></div>
    </div>
    <div class="preview">
      <div id="preview" class="placeholder">Select a session.</div>
    </div>
  </div>
</div>
<div id="toast" class="toast"></div>
<script type="module">
const toastEl = document.getElementById("toast");
let toastTimer = null;
function toast(message) {
  toastEl.textContent = message;
  toastEl.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastEl.classList.remove("show"), 1400);
}

function fmtBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  const units = ["KB", "MB", "GB"];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(value >= 10 ? 0 : 1)} ${units[unit]}`;
}

function fmtWhen(value, mtime) {
  if (value) {
    const date = new Date(value);
    if (!Number.isNaN(date.getTime())) {
      return date.toLocaleString();
    }
  }
  return new Date(mtime * 1000).toLocaleString();
}

function rawUrlFor(item) {
  return `${location.origin}/files/${item.rel.split("/").map(encodeURIComponent).join("/")}`;
}

function viewerUrlFor(item) {
  return `${location.origin}/viewer/?path=${encodeURIComponent(rawUrlFor(item))}`;
}

function fuzzyIncludes(text, needle) {
  let index = 0;
  for (const ch of text) {
    if (ch === needle[index]) index += 1;
    if (index === needle.length) return true;
  }
  return false;
}

function scoreItem(item, query) {
  if (!query) return 0;
  const tokens = query.toLowerCase().split(/\s+/).filter(Boolean);
  const rel = String(item.rel || "").toLowerCase();
  const cwd = String(item.cwd || "").toLowerCase();
  const users = (item.users || []).join(" ").toLowerCase();
  const assistants = (item.assistants || []).join(" ").toLowerCase();
  const hay = [rel, cwd, users, assistants].join(" ");
  let score = 0;

  for (const token of tokens) {
    const direct =
      rel.includes(token) ||
      cwd.includes(token) ||
      users.includes(token) ||
      assistants.includes(token);
    const fuzzy =
      fuzzyIncludes(rel, token) ||
      fuzzyIncludes(cwd, token) ||
      fuzzyIncludes(users, token) ||
      fuzzyIncludes(assistants, token);

    if (!direct && !fuzzy) return -1;

    score += 1;
    if (rel.includes(token)) score += 8;
    else if (fuzzyIncludes(rel, token)) score += 4;

    if (cwd.includes(token)) score += 7;
    else if (fuzzyIncludes(cwd, token)) score += 3;

    if (users.includes(token)) score += 5;
    else if (fuzzyIncludes(users, token)) score += 2;

    if (assistants.includes(token)) score += 2;
  }

  if (query.length >= 2 && rel.startsWith(query.toLowerCase())) score += 12;
  if (query.length >= 2 && cwd.includes(query.toLowerCase())) score += 10;
  if (query.length >= 2 && users.includes(query.toLowerCase())) score += 6;

  return score + (item.started ? 0.001 : 0);
}

const allItems = await fetch("/api/list").then(r => r.json());
let filtered = [];
let activeIndex = 0;

const queryEl = document.getElementById("query");
const listEl = document.getElementById("list");
const previewEl = document.getElementById("preview");
const summaryEl = document.getElementById("summary");

async function copy(text, label) {
  await navigator.clipboard.writeText(text);
  toast(label);
}

function setActive(index) {
  if (!filtered.length) {
    activeIndex = 0;
    renderPreview(null);
    return;
  }
  activeIndex = Math.max(0, Math.min(index, filtered.length - 1));
  renderList();
  renderPreview(filtered[activeIndex]);
  const activeEl = listEl.querySelector(".item.active");
  activeEl?.scrollIntoView({ block: "nearest" });
}

function renderPreview(item) {
  if (!item) {
    previewEl.className = "placeholder";
    previewEl.textContent = "No matching sessions.";
    return;
  }

  const users = (item.users || []).map(text => `<div class="message user">${text}</div>`).join("") || '<div class="message user">No recent user messages.</div>';
  const assistants = (item.assistants || []).map(text => `<div class="message assistant">${text}</div>`).join("") || '<div class="message assistant">No recent assistant messages.</div>';
  const viewerUrl = viewerUrlFor(item);
  const rawUrl = rawUrlFor(item);

  previewEl.className = "";
  previewEl.innerHTML = `
    <div class="preview-inner">
      <h2 class="preview-heading">${item.rel}</h2>
      <div class="meta-grid">
        <div class="meta-row"><div class="meta-label">Started</div><div class="meta-value">${fmtWhen(item.started, item.mtime)}</div></div>
        <div class="meta-row"><div class="meta-label">CWD</div><div class="meta-value">${item.cwd || "-"}</div></div>
        <div class="meta-row"><div class="meta-label">File</div><div class="meta-value">${item.path}</div></div>
        <div class="meta-row"><div class="meta-label">Size</div><div class="meta-value">${fmtBytes(item.size)}</div></div>
      </div>
      <div class="actions">
        <a href="${viewerUrl}" target="_blank" rel="noreferrer">Open in Euphony</a>
        <button class="secondary" data-copy-viewer>Copy viewer URL</button>
        <a class="secondary" href="${rawUrl}" target="_blank" rel="noreferrer">Open raw</a>
        <button class="tertiary" data-copy-raw>Copy raw URL</button>
      </div>
      <div class="section-title">Recent User Messages</div>
      <div class="message-list">${users}</div>
      <div class="section-title">Recent Assistant Messages</div>
      <div class="message-list">${assistants}</div>
    </div>
  `;
  previewEl.querySelector("[data-copy-viewer]")?.addEventListener("click", () => copy(viewerUrl, "Copied viewer URL"));
  previewEl.querySelector("[data-copy-raw]")?.addEventListener("click", () => copy(rawUrl, "Copied raw URL"));
}

function renderList() {
  summaryEl.textContent = `${filtered.length} session file${filtered.length === 1 ? "" : "s"}`;
  listEl.innerHTML = filtered.map((item, index) => `
    <div class="item ${index === activeIndex ? "active" : ""}" data-index="${index}">
      <div class="item-top">
        <div class="item-date">${fmtWhen(item.started, item.mtime)}</div>
        <div class="item-rel">${item.rel}</div>
      </div>
      <div class="item-cwd">${item.cwd || "-"}</div>
      <p class="item-user"><span class="item-label">User:</span> ${(item.users && item.users[0]) || "No recent user message."}</p>
      <p class="item-assistant"><span class="item-label">Assistant:</span> ${(item.assistants && item.assistants[0]) || "No recent assistant message."}</p>
    </div>
  `).join("");

  listEl.querySelectorAll(".item").forEach(el => {
    el.addEventListener("click", () => setActive(Number(el.dataset.index)));
    el.addEventListener("dblclick", () => window.open(viewerUrlFor(filtered[Number(el.dataset.index)]), "_blank"));
  });
}

function recompute() {
  const query = queryEl.value.trim();
  filtered = allItems
    .map(item => ({ item, score: scoreItem(item, query) }))
    .filter(entry => entry.score >= 0)
    .sort((a, b) => b.score - a.score || String(b.item.started).localeCompare(String(a.item.started)))
    .map(entry => entry.item);
  activeIndex = 0;
  renderList();
  renderPreview(filtered[0] || null);
}

queryEl.addEventListener("input", recompute);
queryEl.addEventListener("keydown", event => {
  if (event.key === "ArrowDown") {
    event.preventDefault();
    setActive(activeIndex + 1);
  } else if (event.key === "ArrowUp") {
    event.preventDefault();
    setActive(activeIndex - 1);
  } else if (event.key === "Enter" && filtered[activeIndex]) {
    window.open(viewerUrlFor(filtered[activeIndex]), "_blank");
  }
});

window.addEventListener("keydown", event => {
  if (event.target === queryEl) return;
  if (event.key === "/") {
    event.preventDefault();
    queryEl.focus();
  } else if (event.key === "ArrowDown") {
    event.preventDefault();
    setActive(activeIndex + 1);
  } else if (event.key === "ArrowUp") {
    event.preventDefault();
    setActive(activeIndex - 1);
  } else if (event.key === "Enter" && filtered[activeIndex]) {
    window.open(viewerUrlFor(filtered[activeIndex]), "_blank");
  }
});

document.getElementById("clear").addEventListener("click", () => {
  queryEl.value = "";
  recompute();
  queryEl.focus();
});

document.getElementById("openRoot").addEventListener("click", () => {
  window.open(`${location.origin}/viewer/`, "_blank");
});

recompute();
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, OPTIONS")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_GET(self):
        path = unquote(urlparse(self.path).path)

        if path == "/":
            body = INDEX_HTML.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/api/list":
            body = json.dumps(list_sessions()).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path == "/viewer" or path == "/viewer/":
            candidate = resolve_euphony_path("index.html")
            body = candidate.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path.startswith("/viewer/"):
            candidate = resolve_euphony_path("index.html")
            body = candidate.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if path.startswith("/files/"):
            rel = path[len("/files/"):]
            target = (ROOT / rel).resolve()
            try:
                target.relative_to(ROOT)
            except ValueError:
                self.send_error(404)
                return
            if not target.is_file():
                self.send_error(404)
                return
            body = target.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        try:
            candidate = resolve_euphony_path(path)
        except FileNotFoundError:
            candidate = None

        if candidate is not None and candidate.is_file():
            body = candidate.read_bytes()
            suffix = candidate.suffix
            if suffix == ".js":
                content_type = "text/javascript; charset=utf-8"
            elif suffix == ".css":
                content_type = "text/css; charset=utf-8"
            elif suffix == ".svg":
                content_type = "image/svg+xml"
            elif suffix == ".ico":
                content_type = "image/x-icon"
            elif suffix == ".png":
                content_type = "image/png"
            else:
                content_type = "application/octet-stream"
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_error(404)


if not ROOT.is_dir():
    raise SystemExit(f"Codex sessions root not found: {ROOT}")
if not EUPHONY_DIST.is_dir():
    raise SystemExit(f"Euphony dist not found: {EUPHONY_DIST}")

server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
print(f"Serving {ROOT} on http://127.0.0.1:{PORT}")
server.serve_forever()
PY
}

stop_index_service() {
  launchctl remove "$INDEX_LAUNCH_LABEL" >/dev/null 2>&1 || true
  lsof -tiTCP:"$INDEX_PORT" -sTCP:LISTEN | xargs -r kill >/dev/null 2>&1 || true
}

start_index() {
  launchctl submit -l "$INDEX_LAUNCH_LABEL" -- /bin/bash -lc \
    "CODEX_SESSIONS_ROOT='$ROOT_DIR' EUPHONY_DIST='$EUPHONY_DIR/dist' PORT='$INDEX_PORT' python3 '$INDEX_SERVER_SCRIPT' >'$INDEX_LOG' 2>&1"
}

require_cmd git
require_cmd pnpm
require_cmd python3
require_cmd curl
require_cmd open
require_cmd launchctl
require_cmd osascript

[[ -d "$ROOT_DIR" ]] || fail "Codex sessions directory not found: $ROOT_DIR"

ensure_euphony_repo
ensure_frontend_patch
ensure_frontend_deps
ensure_frontend_build
write_index_server

stop_index_service
start_index
wait_for_http "http://127.0.0.1:$INDEX_PORT/" || fail "Local sessions index did not start. See $INDEX_LOG"

open "http://127.0.0.1:$INDEX_PORT/"
notify "Codex sessions UI launched."
echo "UI: http://127.0.0.1:$INDEX_PORT/"

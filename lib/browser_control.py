#!/usr/bin/env python3
"""Shared macOS browser selection for this repository's Raycast commands."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
SUPPORTED = {'Aside', 'Comet', 'Google Chrome', 'Safari', 'Brave Browser', 'Microsoft Edge'}
HISTORY = {'Aside': 'Aside', 'Comet': 'Comet', 'Google Chrome': 'Google/Chrome',
           'Brave Browser': 'BraveSoftware/Brave-Browser', 'Microsoft Edge': 'Microsoft Edge'}


def config():
    data = json.loads((ROOT / 'browser-config.json').read_text())
    names = data['browsers']
    if not names or len(names) != len(set(names)) or set(names) - SUPPORTED:
        raise ValueError('browsers must contain unique supported browser names')
    if data['default_browser'] not in names:
        raise ValueError('default_browser must be listed in browsers')
    for key in ('reuse_matching_tabs', 'prefer_focused_browser', 'reuse_single_open_browser', 'cycle_matching_tabs'):
        if not isinstance(data.get(key), bool):
            raise ValueError(f'{key} must be true or false')
    return data


def context():
    source = ROOT / 'lib/browser-context.swift'
    cache = Path.home() / 'Library/Caches/raycast-scripts'
    cache.mkdir(parents=True, exist_ok=True)
    binary = cache / ('browser-context-' + hashlib.sha256(source.read_bytes()).hexdigest()[:16])
    if not binary.exists():
        with tempfile.TemporaryDirectory(dir=cache) as tmp:
            compiled = Path(tmp) / 'context'
            subprocess.run(['swiftc', str(source), '-o', str(compiled)], check=True, capture_output=True)
            os.replace(compiled, binary)
    return json.loads(subprocess.check_output([str(binary)], text=True))


def bridge(name, action, data=None):
    result = subprocess.run(['osascript', '-l', 'JavaScript', str(ROOT / 'lib/browser-bridge.js'),
                             name, action, json.dumps(data or {})], text=True, capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError(f'{name}: {result.stderr.strip()}')
    return json.loads(result.stdout) if result.stdout.strip() else None


def inventory(cfg, ctx):
    # Never send events to a closed browser just to discover tabs.
    return {name: bridge(name, 'snapshot') for name in cfg['browsers'] if name in ctx['running']}


def select_browser(cfg, windows, front, patterns=()):
    opened = [name for name in cfg['browsers'] if windows.get(name)]
    matching = [name for name in opened if any(
        matches(t['url'], patterns) for w in windows[name] for t in w['tabs'])]
    candidates = matching if patterns and cfg['reuse_matching_tabs'] and matching else opened
    if cfg['prefer_focused_browser'] and front in candidates:
        return front
    if matching and cfg['reuse_matching_tabs']:
        return cfg['default_browser'] if cfg['default_browser'] in matching else matching[0]
    if cfg['reuse_single_open_browser'] and len(opened) == 1:
        return opened[0]
    return cfg['default_browser']


def matches(url, patterns):
    return any(pattern in url for pattern in patterns)


def select_tab(windows, patterns, cycle):
    tabs = [t for w in windows for t in w['tabs'] if matches(t['url'], patterns)]
    if not tabs:
        return None
    current = next((t for t in windows[0]['tabs'] if t['active']), None)
    if current in tabs:
        return tabs[(tabs.index(current) + 1) % len(tabs)] if cycle else current
    return tabs[0]


def recent_url(name, entry):
    if not entry.get('use_history') or name not in HISTORY:
        return entry['default_url']
    path = Path.home() / 'Library/Application Support' / HISTORY[name] / 'Default/History'
    if not path.exists():
        return entry['default_url']
    try:
        # Read-only SQLite connection includes committed WAL data and does not copy private history.
        with sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=0.2) as db:
            patterns = entry['url_patterns']
            where = ' OR '.join('instr(url, ?) > 0' for _ in patterns)
            row = db.execute(f"SELECT url FROM urls WHERE ({where}) AND url NOT LIKE "
                             "'%/Pages/Auth/Login.aspx%' AND url NOT LIKE '%/Pages/Auth/Logout.aspx%' "
                             "ORDER BY last_visit_time DESC LIMIT 1", patterns).fetchone()
            return row[0] if row else entry['default_url']
    except sqlite3.Error:
        return entry['default_url']


def focus(entry, cfg, ctx, windows):
    name = select_browser(cfg, windows, ctx['front'], entry['url_patterns'])
    tab = select_tab(windows.get(name, []), entry['url_patterns'],
                     cfg['cycle_matching_tabs'] and ctx['front'] == name)
    if tab:
        bridge(name, 'focus', tab)
        return
    if name not in ctx['running']:
        subprocess.run(['open', '-a', name], check=True)
        # Allow session restoration before deciding to create a duplicate tab.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            restored = bridge(name, 'snapshot')
            tab = select_tab(restored, entry['url_patterns'], False)
            if tab:
                bridge(name, 'focus', tab)
                return
            time.sleep(0.25)
    bridge(name, 'open', {'url': recent_url(name, entry)})


def active(cfg, ctx, windows):
    name = select_browser(cfg, windows, ctx['front'])
    if not windows.get(name):
        raise RuntimeError('No unambiguous active browser tab. Focus a browser and try again.')
    tab = next((t for t in windows[name][0]['tabs'] if t['active']), None)
    if tab is None:
        raise RuntimeError(f'{name} has no active tab')
    return {'browser': name, **tab}


def toggle(source, windows):
    path = Path.home() / 'Library/Caches/raycast-scripts/browser-toggle.json'
    try:
        state = json.loads(path.read_text())
    except (FileNotFoundError, ValueError):
        state = {}
    name = source['browser']
    previous = state.get(name)
    valid = previous and any(all(t[k] == previous[k] for k in ('window', 'index', 'url'))
                             for w in windows[name] for t in w['tabs'])
    if valid and any(source[k] != previous[k] for k in ('window', 'index', 'url')):
        bridge(name, 'focus', previous)
    state[name] = source
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['focus', 'focus-url', 'active', 'navigate', 'app-mode', 'toggle', 'inspect'])
    parser.add_argument('value', nargs='?')
    parser.add_argument('--patterns', nargs='+')
    parser.add_argument('--source', help='JSON from active; pins the original tab during slow conversions')
    args = parser.parse_args()
    if args.action == 'navigate':
        if not args.source or not args.value:
            parser.error('navigate requires a URL and --source')
        source = json.loads(args.source)
        if source['browser'] not in SUPPORTED:
            raise ValueError('Unsupported browser')
        bridge(source['browser'], 'navigate', {**source, 'target': args.value})
        return
    cfg, ctx = config(), context()
    windows = inventory(cfg, ctx)
    if args.action == 'inspect':
        print(json.dumps({'default': cfg['default_browser'], 'front': ctx['front'],
                          'open_windows': {n: len(w) for n, w in windows.items()},
                          'selected': select_browser(cfg, windows, ctx['front'])}))
    elif args.action == 'focus-url':
        if not args.value:
            parser.error('focus-url requires a URL')
        focus({'default_url': args.value, 'url_patterns': args.patterns or [args.value]}, cfg, ctx, windows)
    elif args.action == 'focus':
        entries = json.loads((ROOT / 'focus-configs.json').read_text())
        entry = next((e for e in entries if e['name'] == args.value), None)
        if entry is None:
            raise ValueError(f'Unknown focus command: {args.value}')
        focus(entry, cfg, ctx, windows)
    else:
        source = active(cfg, ctx, windows)
        if args.action == 'active':
            print(json.dumps(source))
        elif args.action == 'toggle':
            toggle(source, windows)
        elif args.action == 'app-mode':
            name = source['browser']
            if urlsplit(source['url']).scheme not in {'http', 'https', 'file'}:
                raise RuntimeError('App mode requires a web page or local file')
            if name == 'Safari':
                raise RuntimeError('Safari does not support Chromium app mode')
            app = Path('/Applications') / (name + '.app')
            with (app / 'Contents/Info.plist').open('rb') as f:
                executable = plistlib.load(f)['CFBundleExecutable']
            subprocess.Popen([str(app / 'Contents/MacOS' / executable), '--app=' + source['url']],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            existing = {w['id'] for w in windows[name]}
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                current = bridge(name, 'snapshot')
                target = next((t for w in current if w['id'] not in existing
                               for t in w['tabs'] if t['url'] == source['url']), None)
                if target:
                    bridge(name, 'focus', target)
                    bridge(name, 'close', source)
                    return
                time.sleep(0.2)
            raise RuntimeError('App window could not be verified; the source tab was kept open')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, RuntimeError, subprocess.SubprocessError, OSError) as error:
        print(f'Browser command failed: {error}', file=sys.stderr)
        sys.exit(1)

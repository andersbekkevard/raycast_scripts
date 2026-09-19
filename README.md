Raycast scripts for different things. 
Primary is to focus/switch between browser tabs matching URL patterns.
Includes generator for creating focus scripts from JSON config, with optional browser history lookup to open most recently visited URLs.
Configure in `focus-configs.json` and regenerate with `generate-history-scripts.sh`.

`other/raycast-beta-dictation-english.sh` and `other/raycast-beta-dictation-norwegian.sh` set the Dictation language in Raycast Beta only. They use the visible Raycast Beta settings controls and require Accessibility permission for Raycast Beta.

## Voice Keys

`hammerspoon/voice_keys.lua` turns spoken keyboard chords into real keypresses. Press the lower M650 side button and speak immediately. Hammerspoon records with SoX, stops after 550 ms of speech-ending silence, sends the WAV to TypeWhisper's local CLI using Groq Whisper Large V3 Turbo, parses the result without an LLM, and emits the chord. An eight-second safety timeout stops abandoned recordings.

Initial semantic commands are `undo`, `redo`, `copy`, `paste`, `select all`, `escape`, and `enter`. The generic grammar accepts commands such as `command W`, `command shift Z`, `control shift tab`, and `super 1`. `super` matches Raycast's Hyper Key: Command + Option + Control. It is configurable in `hammerspoon/init.lua`.

The live Hammerspoon config loads `hammerspoon/init.lua`. The M650 mapping is: front side button keeps its Option-Space dictation Smart Action, the lower side button uses Logi's Middle button action as the Voice Keys trigger, and wheel click sends Return. Logi collapses programmable-button holds into taps, so Voice Keys starts on that tap and uses silence detection rather than button release to stop.

Visual state feedback appears immediately: green `Listening` confirms the trigger reached Hammerspoon, amber `Transcribing` confirms release and processing, blue `Executed …` confirms key emission, and red text identifies an error. No feedback means the failure is before Hammerspoon.

Run the parser tests with:

```sh
lua tests/test_voice_keys_parser.lua
```

## Shared browser control (macOS)

`browser-config.json` is the single browser preference for this repository.
Change `default_browser` to `Aside`, `Comet`, `Google Chrome`, or `Safari`.
The `browsers` array lists browsers to inspect, in tie-break order; the helper
also supports `Brave Browser` and `Microsoft Edge` when explicitly listed.
Changes take effect on the next command, without regenerating scripts.
This does not change the macOS default browser or Linux/agent browser settings.

Focus commands first reuse a matching tab in an open browser, preferring the
browser in use, then the default, then configured order. Without a matching tab,
they use the focused browser, the only browser with windows, or the default.
A running process with no windows does not count as an open browser. Set
`reuse_matching_tabs`, `prefer_focused_browser`, or `reuse_single_open_browser`
to false to disable that part of selection.

A first press brings a background browser's selected matching tab forward.
Further presses cycle matching tabs within that browser when
`cycle_matching_tabs` is true. With Raycast in front, the helper uses the first
ordinary application window behind its overlay to identify the invoking app.
Hidden windows remain eligible for matching-tab reuse.

All focus wrappers and the older ChatGPT, Messenger, Meet, Gemini and Notion
commands use `lib/browser_control.py`. PDF conversions pin the source window,
tab and URL so finishing a conversion cannot overwrite whichever tab you have
since switched to. App mode opens and verifies a Chromium app window before
closing the source; Safari reports that app mode is unsupported. Toggle Recent
Tabs remembers the last tab seen by that command separately for each browser;
it does not track tab changes made between invocations.

History lookup uses the selected Chromium browser's Default profile, with a
read-only SQLite connection. Safari and unavailable/locked histories fall back
to the command's default URL. The Comet-extension YouTube summary command is an
explicit exception: its extension transport and destination remain Comet.
The older non-extension Python summary script follows shared browser selection.

Requires macOS, Python 3, Apple Events permission for the configured browsers,
and Swift command-line tools. The tiny window-context helper compiles once into
`~/Library/Caches/raycast-scripts/`; it inspects window order, not window content.
Browser discovery failures are surfaced instead of silently opening duplicates.

Run `python3 lib/browser_control.py inspect` to see routing without changing tabs.
Run `python3 -m unittest discover -s tests -p test_browser_control.py` for policy
checks. `generate-history-scripts.sh` regenerates Raycast metadata wrappers from
`focus-configs.json`, and works from any directory.

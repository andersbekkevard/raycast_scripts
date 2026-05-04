#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Kokoro Set Voice
# @raycast.mode silent

# Optional parameters:
# @raycast.argument1 { "type": "dropdown", "placeholder": "Voice", "data": [{"title":"af_heart - American female default","value":"af_heart"},{"title":"af_bella - American female high quality","value":"af_bella"},{"title":"af_nicole - American female soft","value":"af_nicole"},{"title":"af_sarah - American female","value":"af_sarah"},{"title":"af_sky - American female","value":"af_sky"},{"title":"af_alloy - American female","value":"af_alloy"},{"title":"af_aoede - American female","value":"af_aoede"},{"title":"af_jessica - American female","value":"af_jessica"},{"title":"af_kore - American female","value":"af_kore"},{"title":"af_nova - American female","value":"af_nova"},{"title":"af_river - American female","value":"af_river"},{"title":"am_fenrir - American male","value":"am_fenrir"},{"title":"am_michael - American male","value":"am_michael"},{"title":"am_puck - American male","value":"am_puck"},{"title":"am_adam - American male","value":"am_adam"},{"title":"am_echo - American male","value":"am_echo"},{"title":"am_eric - American male","value":"am_eric"},{"title":"am_liam - American male","value":"am_liam"},{"title":"am_onyx - American male","value":"am_onyx"},{"title":"am_santa - American male","value":"am_santa"},{"title":"bf_emma - British female","value":"bf_emma"},{"title":"bf_isabella - British female","value":"bf_isabella"},{"title":"bf_alice - British female","value":"bf_alice"},{"title":"bf_lily - British female","value":"bf_lily"},{"title":"bm_george - British male","value":"bm_george"},{"title":"bm_lewis - British male","value":"bm_lewis"},{"title":"bm_daniel - British male","value":"bm_daniel"},{"title":"bm_fable - British male","value":"bm_fable"}] }

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Set the default Kokoro voice

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/kokoro_paths.sh"

kokoro_require_cmd python3

python3 "$SCRIPT_DIR/kokoro_client.py" set-voice "$1"

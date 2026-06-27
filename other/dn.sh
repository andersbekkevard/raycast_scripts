#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title dn
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📈
# @raycast.argument1 { "type": "text", "placeholder": "Company or ticker" }
# @raycast.packageName DN Investor

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Open the best matching DN Investor stock page

set -euo pipefail

QUERY="${1:-}"
QUERY="$(printf "%s" "$QUERY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

if [ -z "$QUERY" ]; then
    echo "Missing company or ticker"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required"
    exit 1
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/raycast-dn-investor"
CACHE_FILE="$CACHE_DIR/overview.json"
API_URL="https://inv-marketvector-api.dn.no/api/v1/models/overview"

mkdir -p "$CACHE_DIR"

cache_is_fresh() {
    [ -f "$CACHE_FILE" ] || return 1

    local modified_at now max_age
    modified_at="$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    max_age=$((12 * 60 * 60))

    [ $((now - modified_at)) -lt "$max_age" ]
}

refresh_cache() {
    local temp_file
    temp_file="$(mktemp "${CACHE_DIR}/overview.XXXXXX")"

    if curl -fsSL "$API_URL" -o "$temp_file"; then
        mv "$temp_file" "$CACHE_FILE"
    else
        rm -f "$temp_file"
        [ -f "$CACHE_FILE" ]
    fi
}

if ! cache_is_fresh; then
    refresh_cache || {
        echo "Could not fetch DN Investor instruments"
        exit 1
    }
fi

MATCH="$(
    jq -r --arg q "$QUERY" '
        def norm: ascii_downcase;
        def qnorm: $q | norm;

        .result.prefetched
        | map({
            id: .[0],
            name: .[1],
            exchange: .[3],
            ticker: .[6],
            score: (
                if ((.[6] // "") | norm) == qnorm then 100
                elif ((.[1] // "") | norm) == qnorm then 90
                elif ((.[6] // "") | norm | startswith(qnorm)) then 80
                elif ((.[1] // "") | norm | startswith(qnorm)) then 70
                elif ((.[6] // "") | norm | contains(qnorm)) then 60
                elif ((.[1] // "") | norm | contains(qnorm)) then 50
                else 0
                end
            )
        })
        | map(select((.id | startswith("S")) and .score > 0))
        | sort_by(-.score, .name)
        | .[0]
        | select(. != null)
        | [.id, .ticker, (.name | @uri), .name]
        | @tsv
    ' "$CACHE_FILE"
)"

if [ -z "$MATCH" ]; then
    echo "No DN Investor match for $QUERY"
    exit 1
fi

IFS=$'\t' read -r INSTRUMENT_ID TICKER ENCODED_NAME NAME <<< "$MATCH"
URL="https://www.dn.no/investor/aksje/${INSTRUMENT_ID}/${TICKER}/${ENCODED_NAME}"

open "$URL"
echo "$NAME"

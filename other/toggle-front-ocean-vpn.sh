#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Front Ocean VPN
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🛡️

# Documentation:
# @raycast.author Anders Bekkevard
# @raycast.description Connects or disconnects the Front Ocean VPN network service

VPN_NAME="Front Ocean VPN"

if ! scutil --nc list | grep -F "\"$VPN_NAME\"" > /dev/null; then
  echo "VPN service not found: $VPN_NAME"
  exit 1
fi

STATUS=$(scutil --nc status "$VPN_NAME" 2>&1 | sed -n '1p')

case "$STATUS" in
  Connected)
    if scutil --nc stop "$VPN_NAME" > /dev/null; then
      echo "$VPN_NAME: disconnecting"
    else
      echo "$VPN_NAME: failed to disconnect"
      exit 1
    fi
    ;;
  Connecting|Disconnecting)
    echo "$VPN_NAME: already $STATUS"
    ;;
  *)
    if scutil --nc start "$VPN_NAME" > /dev/null; then
      echo "$VPN_NAME: connecting"
    else
      echo "$VPN_NAME: failed to connect"
      exit 1
    fi
    ;;
esac

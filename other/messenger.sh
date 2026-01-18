#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Messenger Toggle
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💬

# Documentation:
# @raycast.author Anders Bekkevard

STATE_FILE="$HOME/.cache/raycast-messenger-toggle-state"
mkdir -p "$(dirname "$STATE_FILE")"

# Function to maximize Comet window 1 to fill the screen
maximize_window() {
    osascript <<'MAXEOF'
tell application "Finder"
    set screenBounds to bounds of window of desktop
    set screenWidth to item 3 of screenBounds
    set screenHeight to item 4 of screenBounds
end tell
tell application "Comet"
    if (count of windows) > 0 then
        set bounds of window 1 to {0, 25, screenWidth, screenHeight}
    end if
end tell
MAXEOF
}

# Get the frontmost app using lsappinfo (avoids System Events permissions)
FRONTMOST_APP=$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | cut -d'"' -f4)

# Check if Comet is already running
if pgrep -x "Comet" > /dev/null; then
    # Get current state: is Messenger the frontmost window?
    MESSENGER_IS_FRONT=$(osascript <<'EOF'
tell application "Comet"
    if (count of windows) is 0 then return "no"
    try
        set tabURL to URL of active tab of window 1
        if tabURL contains "messenger.com" then return "yes"
    end try
    set windowTitle to name of window 1
    if windowTitle contains "Messenger" or windowTitle contains "messenger" then return "yes"
end tell
return "no"
EOF
)

    if [ "$FRONTMOST_APP" = "Comet" ] && [ "$MESSENGER_IS_FRONT" = "yes" ]; then
        # Messenger is focused - toggle OFF: restore previous state
        if [ -f "$STATE_FILE" ]; then
            PREV_APP=$(cat "$STATE_FILE")
            rm "$STATE_FILE"
            if [ "$PREV_APP" = "Comet" ]; then
                # Previous was another Comet window - bring window 2 to front
                osascript -e 'tell application "Comet" to if (count of windows) > 1 then set index of window 2 to 1'
            else
                # Previous was a different app - activate it
                osascript -e "tell application \"$PREV_APP\" to activate"
            fi
        else
            # No saved state - just bring next window or do nothing
            osascript -e 'tell application "Comet" to if (count of windows) > 1 then set index of window 2 to 1'
        fi
    else
        # Messenger not focused - toggle ON: save current state and focus Messenger
        echo "$FRONTMOST_APP" > "$STATE_FILE"

        RESULT=$(osascript <<'EOF'
tell application "Comet"
    set messengerIndex to -1
    set windowCount to count of windows

    repeat with i from 1 to windowCount
        set w to window i
        set isMessengerWindow to false

        try
            set tabURL to URL of active tab of w
            if tabURL contains "messenger.com" then
                set isMessengerWindow to true
            end if
        end try

        if not isMessengerWindow then
            set windowTitle to name of w
            if windowTitle contains "Messenger" or windowTitle contains "messenger" or windowTitle contains "messenger.com" then
                set isMessengerWindow to true
            end if
        end if

        if isMessengerWindow then
            set messengerIndex to i
            exit repeat
        end if
    end repeat

    if messengerIndex is -1 then
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://messenger.com' &> /dev/null &"
        return "new"
    else
        activate
        set index of window messengerIndex to 1
        return "existing"
    end if
end tell
EOF
)
        if [ "$RESULT" = "new" ]; then
            # Wait for new window to appear, then maximize
            sleep 0.1
        fi
        maximize_window
    fi
else
    # Comet is not running - save current app and launch Messenger
    echo "$FRONTMOST_APP" > "$STATE_FILE"
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://messenger.com" &
    sleep 0.4
    maximize_window
fi

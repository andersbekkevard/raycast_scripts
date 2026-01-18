#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ChatGPT Toggle 
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author Anders Bekkevard

STATE_FILE="$HOME/.cache/raycast-chatgpt-toggle-state"
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
    # Get current state: is ChatGPT the frontmost window?
    CHATGPT_IS_FRONT=$(osascript <<'EOF'
tell application "Comet"
    if (count of windows) is 0 then return "no"
    try
        set tabURL to URL of active tab of window 1
        if tabURL contains "chat.openai.com" or tabURL contains "chatgpt.com" then return "yes"
    end try
    set windowTitle to name of window 1
    if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" then return "yes"
end tell
return "no"
EOF
)

    if [ "$FRONTMOST_APP" = "Comet" ] && [ "$CHATGPT_IS_FRONT" = "yes" ]; then
        # ChatGPT is focused - toggle OFF: restore previous state
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
        # ChatGPT not focused - toggle ON: save current state and focus ChatGPT
        echo "$FRONTMOST_APP" > "$STATE_FILE"

        RESULT=$(osascript <<'EOF'
tell application "Comet"
    set chatgptIndex to -1
    set windowCount to count of windows

    repeat with i from 1 to windowCount
        set w to window i
        set isChatGPTWindow to false

        try
            set tabURL to URL of active tab of w
            if tabURL contains "chat.openai.com" or tabURL contains "chatgpt.com" then
                set isChatGPTWindow to true
            end if
        end try

        if not isChatGPTWindow then
            set windowTitle to name of w
            if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" or windowTitle contains "chatgpt.com" then
                set isChatGPTWindow to true
            end if
        end if

        if isChatGPTWindow then
            set chatgptIndex to i
            exit repeat
        end if
    end repeat

    if chatgptIndex is -1 then
        do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' &> /dev/null &"
        return "new"
    else
        activate
        set index of window chatgptIndex to 1
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
    # Comet is not running - save current app and launch ChatGPT
    echo "$FRONTMOST_APP" > "$STATE_FILE"
    /Applications/Comet.app/Contents/MacOS/Comet --app="https://chatgpt.com" &
    sleep 0.4
    maximize_window
fi
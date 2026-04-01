#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title YouTube App Mode
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📺

# Documentation:
# @raycast.description Reopen current Comet tab in app mode (borderless window, great for fullscreen YouTube)
# @raycast.author Anders Bekkevard

URL=$(osascript <<'EOF'
tell application "Comet"
    if (count of windows) is 0 then
        return "error:no_window"
    end if
    try
        set tabURL to URL of active tab of front window
        return tabURL
    on error
        return "error:no_tab"
    end try
end tell
EOF
)

if [[ "$URL" == error:* ]]; then
    echo "No active Comet tab found"
    exit 1
fi

# Close the current tab
osascript <<'EOF'
tell application "Comet"
    if (count of windows) > 0 then
        tell front window
            if (count of tabs) > 1 then
                close active tab
            else
                -- Only tab left, close the window
                close
            end if
        end tell
    end if
end tell
EOF

# Reopen in app mode and maximize
osascript <<EOF
tell application "Finder"
    set screenBounds to bounds of window of desktop
    set screenWidth to item 3 of screenBounds
    set screenHeight to item 4 of screenBounds
end tell
tell application "Comet"
    do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='$URL' &> /dev/null &"
    delay 0.3
    activate
    if (count of windows) > 0 then
        set bounds of window 1 to {0, 25, screenWidth, screenHeight}
    end if
end tell
EOF

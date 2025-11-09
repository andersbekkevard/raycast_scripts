#!/usr/bin/env python3

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ChatGPT Toggle (Python)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author Anders Bekkevard

import subprocess
import sys


def execute_applescript(script):
    """Execute an AppleScript and return the output."""
    try:
        result = subprocess.run(
            ["osascript", "-e", script], capture_output=True, text=True, check=False
        )
        return {
            "output": result.stdout.strip(),
            "error": result.stderr.strip(),
            "success": result.returncode == 0,
        }
    except Exception as e:
        return {"output": "", "error": str(e), "success": False}


def main():
    # Check if Comet is running
    comet_running_check = """
        tell application "System Events"
            return (name of processes) contains "Comet"
        end tell
    """

    comet_running_result = execute_applescript(comet_running_check)
    comet_is_running = comet_running_result["output"] == "true"

    # Find ChatGPT window and get state information
    find_chatgpt_window = """
        tell application "System Events"
            set cometRunning to (name of processes) contains "Comet"
            if not cometRunning then
                return "NOT_RUNNING"
            end if
        end tell
        
        tell application "Comet"
            set chatgptWindow to missing value
            set chatgptWindowIndex to -1
            set windowCount to count of windows
            set isFrontmost to false
            
            -- Find ChatGPT window and check if it's frontmost (window 1)
            repeat with i from 1 to windowCount
                set w to window i
                set windowTitle to name of w
                if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" then
                    set chatgptWindow to w
                    set chatgptWindowIndex to i
                    -- Window 1 is always the frontmost window
                    set isFrontmost to (i is 1)
                    exit repeat
                end if
            end repeat
            
            if chatgptWindowIndex is -1 then
                return "NO_CHATGPT_WINDOW|" & windowCount
            else
                return "CHATGPT_EXISTS|" & chatgptWindowIndex & "|" & isFrontmost & "|" & windowCount
            end if
        end tell
    """

    window_state_result = execute_applescript(find_chatgpt_window)
    window_state = window_state_result["output"]

    # Parse the state
    parts = window_state.split("|")
    state = parts[0]

    if state == "NOT_RUNNING":
        # Journey 1: Comet is not running, launch it with ChatGPT
        launch_script = """
            do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' &> /dev/null &"
        """
        execute_applescript(launch_script)

    elif state == "NO_CHATGPT_WINDOW":
        # Journey 6: Comet is running but no ChatGPT window exists
        window_count = int(parts[1]) if len(parts) > 1 else 0
        create_chatgpt_script = """
            tell application "Comet"
                activate
                do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' &> /dev/null &"
            end tell
        """
        execute_applescript(create_chatgpt_script)

    elif state == "CHATGPT_EXISTS":
        chatgpt_index = int(parts[1]) if len(parts) > 1 else -1
        is_frontmost = parts[2] == "true" if len(parts) > 2 else False
        window_count = int(parts[3]) if len(parts) > 3 else 0

        # Check if Comet is the frontmost application
        check_frontmost = """
            tell application "System Events"
                set frontmostApp to name of first application process whose frontmost is true
                return frontmostApp is "Comet"
            end tell
        """

        frontmost_result = execute_applescript(check_frontmost)
        comet_is_frontmost = frontmost_result["output"] == "true"

        if comet_is_frontmost and is_frontmost:
            # Journey 3 & 3b: ChatGPT is in focus
            if window_count > 1:
                # Journey 3: There are other Comet windows, switch to the next one
                switch_to_next_window = f"""
                    tell application "Comet"
                        set nextWindowIndex to {chatgpt_index} + 1
                        if nextWindowIndex > {window_count} then
                            set nextWindowIndex to 1
                        end if
                        
                        -- Make sure we're not switching to ChatGPT itself
                        if nextWindowIndex is not {chatgpt_index} then
                            set index of window nextWindowIndex to 1
                        end if
                    end tell
                """
                execute_applescript(switch_to_next_window)
            else:
                # Journey 3b: ChatGPT is the only window, hide Comet
                hide_comet = """
                    tell application "System Events"
                        tell process "Comet"
                            keystroke "h" using command down
                        end tell
                    end tell
                """
                execute_applescript(hide_comet)
        else:
            # Journey 2, 4, 5: ChatGPT exists but is not in focus, bring it to front
            bring_to_front = """
                tell application "Comet"
                    activate
                    set windowFound to false
                    repeat with w in windows
                        set windowTitle to name of w
                        if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" then
                            set index of w to 1
                            set windowFound to true
                            exit repeat
                        end if
                    end repeat
                end tell
            """
            execute_applescript(bring_to_front)

    sys.exit(0)


if __name__ == "__main__":
    main()

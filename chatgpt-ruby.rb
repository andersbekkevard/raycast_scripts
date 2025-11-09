#!/usr/bin/env ruby

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ChatGPT Toggle (Ruby)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author Anders Bekkevard

require 'open3'

def execute_applescript(script)
  stdout, stderr, status = Open3.capture3('osascript', '-e', script)
  { output: stdout.chomp, error: stderr.chomp, success: status.success? }
end

# Check if Comet is running
comet_running_check = <<~APPLESCRIPT
  tell application "System Events"
    return (name of processes) contains "Comet"
  end tell
APPLESCRIPT

comet_running_result = execute_applescript(comet_running_check)
comet_is_running = comet_running_result[:output] == "true"

# Find ChatGPT window and get state information
find_chatgpt_window = <<~APPLESCRIPT
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
APPLESCRIPT

window_state_result = execute_applescript(find_chatgpt_window)
window_state = window_state_result[:output]

# Parse the state
parts = window_state.split("|")
state = parts[0]

if state == "NOT_RUNNING"
  # Journey 1: Comet is not running, launch it with ChatGPT
  launch_script = <<~APPLESCRIPT
    do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' &> /dev/null &"
  APPLESCRIPT
  execute_applescript(launch_script)
elsif state == "NO_CHATGPT_WINDOW"
  # Journey 6: Comet is running but no ChatGPT window exists
  window_count = parts[1].to_i
  create_chatgpt_script = <<~APPLESCRIPT
    tell application "Comet"
      activate
      do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' &> /dev/null &"
    end tell
  APPLESCRIPT
  execute_applescript(create_chatgpt_script)
elsif state == "CHATGPT_EXISTS"
  chatgpt_index = parts[1].to_i
  is_frontmost = parts[2] == "true"
  window_count = parts[3].to_i
  
  # Check if Comet is the frontmost application
  check_frontmost = <<~APPLESCRIPT
    tell application "System Events"
      set frontmostApp to name of first application process whose frontmost is true
      return frontmostApp is "Comet"
    end tell
  APPLESCRIPT
  
  frontmost_result = execute_applescript(check_frontmost)
  comet_is_frontmost = frontmost_result[:output] == "true"
  
  if comet_is_frontmost && is_frontmost
    # Journey 3 & 3b: ChatGPT is in focus
    if window_count > 1
      # Journey 3: There are other Comet windows, switch to the next one
      switch_to_next_window = <<~APPLESCRIPT
        tell application "Comet"
          set nextWindowIndex to #{chatgpt_index} + 1
          if nextWindowIndex > #{window_count} then
            set nextWindowIndex to 1
          end if
          
          -- Make sure we're not switching to ChatGPT itself
          if nextWindowIndex is not #{chatgpt_index} then
            set index of window nextWindowIndex to 1
          end if
        end tell
      APPLESCRIPT
      execute_applescript(switch_to_next_window)
    else
      # Journey 3b: ChatGPT is the only window, hide Comet
      hide_comet = <<~APPLESCRIPT
        tell application "System Events"
          tell process "Comet"
            keystroke "h" using command down
          end tell
        end tell
      APPLESCRIPT
      execute_applescript(hide_comet)
    end
  else
    # Journey 2, 4, 5: ChatGPT exists but is not in focus, bring it to front
    bring_to_front = <<~APPLESCRIPT
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
    APPLESCRIPT
    execute_applescript(bring_to_front)
  end
end

exit(0)

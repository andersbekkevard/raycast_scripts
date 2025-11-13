#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title ChatGPT Toggle (AppleScript)
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🤖

# Documentation:
# @raycast.author Anders Bekkevard

on isCometRunning()
	tell application "System Events"
		return (name of processes) contains "Comet"
	end tell
end isCometRunning

on findChatGPTWindow()
	tell application "Comet"
		repeat with w in windows
			set windowTitle to name of w
			if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" then
				return w
			end if
		end repeat
	end tell
	return missing value
end findChatGPTWindow

on isChatGPTFrontmost()
	tell application "Comet"
		if (count of windows) is 0 then return false
		
		set frontWindow to window 1
		set frontTitle to name of frontWindow
		
		if frontTitle contains "ChatGPT" or frontTitle contains "chatgpt" or frontTitle contains "chat.openai.com" then
			return true
		else
			return false
		end if
	end tell
end isChatGPTFrontmost

-- Main logic
if not isCometRunning() then
	-- Comet is not running, launch it with ChatGPT
	do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' > /dev/null 2>&1 &"
else
	set chatGPTWindow to findChatGPTWindow()
	
	if chatGPTWindow is missing value then
		-- No ChatGPT window exists, launch one
		do shell script "/Applications/Comet.app/Contents/MacOS/Comet --app='https://chatgpt.com' > /dev/null 2>&1 &"
	else

		-- ChatGPT window exists
		tell application "System Events"
			set cometIsFrontmost to (name of first application process whose frontmost is true) is "Comet"
		end tell
		
		if cometIsFrontmost and isChatGPTFrontmost() then
			-- ChatGPT is in focus, toggle it off
			tell application "Comet"
				set windowCount to count of windows
				
				if windowCount > 1 then
					-- Multiple windows: bring next window to front
					set chatgptIndex to -1
					
					-- Find ChatGPT window index
					repeat with i from 1 to windowCount
						set w to window i
						set windowTitle to name of w
						if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" then
							set chatgptIndex to i
							exit repeat
						end if
					end repeat
					
					if chatgptIndex is not -1 then
						-- Find next window
						set nextWindowIndex to chatgptIndex + 1
						if nextWindowIndex > windowCount then
							set nextWindowIndex to 1
						end if
						
						-- Bring next window to front (if it's not the same window)
						if nextWindowIndex is not chatgptIndex then
							set index of window nextWindowIndex to 1
						end if
					end if
				else
					-- Only ChatGPT window exists: hide the app
					tell application "System Events"
						set visible of process "Comet" to false
					end tell
				end if
			end tell
		else
			-- ChatGPT exists but not in focus, bring it to front
			tell application "Comet"
				activate
				
				repeat with w in windows
					set windowTitle to name of w
					if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" then
						set index of w to 1
						exit repeat
					end if
				end repeat
			end tell
		end if
	end if
end if


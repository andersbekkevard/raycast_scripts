- [ ] Inspired by this one, make some scripts relating to Apple Notes, for example the scribbledown one.
#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Append Content From Clipboard
# @raycast.mode silent

# Optional parameters:
# @raycast.icon ./images/notes.png
# @raycast.argument1 { "type": "text", "placeholder": "Note Name" }
# @raycast.packageName Notes

# Documentation:
# @raycast.description Script to append to an existing note content from clipboard.
# @raycast.author Ayoub Gharbi
# @raycast.authorURL https://github.com/ayoub-g

on run argv 
	tell application "Notes"
		set note_name to (item 1 of argv)
		if exists note note_name then
			
			show note note_name
			set new_content to the clipboard
			set note_content to body of note note_name 
			set body of note note_name to note_content & new_content
		else
			log "Note \"" & note_name & "\" was not found"
		end if
	end tell
end run


# Clipboard related
Great question! Here are some useful clipboard transformations you might find handy:

**Text Cleanup:**
- **Remove extra whitespace** - Collapse multiple spaces/tabs into single spaces
- **Trim whitespace** - Strip leading/trailing spaces from each line
- **Remove empty lines** - Clean up text with lots of blank lines
- **Smart quotes → straight quotes** - Fix curly quotes from Word/Pages (`"` → `"`)

**Case Conversion:**
- **UPPERCASE / lowercase / Title Case** - Quick text case changes
- **Slugify** - Convert to URL-friendly format (`My Title` → `my-title`)

**Developer Tools:**
- **JSON prettify / minify** - Format or compress JSON
- **URL encode / decode** - Handle special characters in URLs
- **Base64 encode / decode** - Quick encoding
- **Escape HTML** - Convert `<` to `&lt;` etc.
- **Sort lines** - Alphabetically sort clipboard lines
- **Remove duplicate lines** - Dedupe a list

**Extraction:**
- **Extract URLs** - Pull all URLs from text
- **Extract emails** - Pull all email addresses from text

**Stats:**
- **Word/character count** - Quick clipboard stats (show in notification)

Would you like me to create any of these? I can make a few that seem most useful to you, or create a whole set if you want a clipboard toolkit.
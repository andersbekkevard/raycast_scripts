# ChatGPT Toggle - Behavior Specification

## Overview
A Raycast script that toggles a ChatGPT window running in the Comet browser. The script intelligently detects whether a ChatGPT window exists and whether it's currently in focus, then takes the appropriate action.

## Core Principles
1. **Window-specific detection**: The script must detect ChatGPT windows specifically, not just any Comet window
2. **Hidden window awareness**: The script must find ChatGPT windows even when they're hidden or inactive
3. **Smart toggle behavior**: Only hide when the ChatGPT window is actually in focus; otherwise bring it to focus
4. **No duplicate windows**: Never create a second ChatGPT window if one already exists

## User Journeys

### Journey 1: First Launch (No Comet Running)
**Initial State:**
- Comet is not running
- No Comet windows exist

**User Action:**
- User triggers the Raycast command

**Expected Behavior:**
- Comet launches
- ChatGPT opens in a new window
- User sees ChatGPT interface

**Final State:**
- User is viewing ChatGPT and can start a conversation

---

### Journey 2: ChatGPT Window Exists But Is Hidden
**Initial State:**
- Comet is running
- ChatGPT window exists but Comet is hidden (Cmd+H previously pressed)
- User is currently in a different application (e.g., Cursor, Chrome, etc.)

**User Action:**
- User triggers the Raycast command

**Expected Behavior:**
- Comet becomes visible
- ChatGPT window appears in focus
- User can immediately continue their conversation

**Final State:**
- User is viewing their ChatGPT conversation
- Previous conversation state is preserved

---

### Journey 3: ChatGPT Window Is In Focus (With Other Comet Windows)
**Initial State:**
- Comet is running and is the frontmost application
- User has multiple Comet windows open (e.g., YouTube, ChatGPT)
- ChatGPT window is the frontmost Comet window (user can see it)
- User is actively looking at ChatGPT

**User Action:**
- User triggers the Raycast command

**Expected Behavior:**
- ChatGPT disappears from view
- The previous Comet window (e.g., YouTube) returns to focus
- ChatGPT conversation remains intact in the background

**Final State:**
- User is back to viewing their previous Comet window (e.g., YouTube)
- Comet remains the active application
- ChatGPT window is still open but no longer visible
- User can quickly toggle back to resume their ChatGPT conversation

**CRITICAL:** The ChatGPT window must NOT be closed - it should remain open in the background so the user can quickly toggle back to their conversation.

---

### Journey 3b: ChatGPT Window Is In Focus (Only Comet Window)
**Initial State:**
- Comet is running and is the frontmost application
- ChatGPT is the ONLY Comet window open (no YouTube or other windows)
- User is actively looking at ChatGPT

**User Action:**
- User triggers the Raycast command

**Expected Behavior:**
- Comet disappears entirely (like pressing Cmd+H)
- User returns to the previous application they were using (e.g., Cursor)

**Final State:**
- User is back in their previous application (e.g., Cursor)
- Comet is hidden but still running
- ChatGPT conversation is preserved and can be toggled back

**Note:** This is the fallback behavior when there's no other Comet window to switch to.

---

### Journey 4: User Is In A Different Comet Window (e.g., YouTube)
**Initial State:**
- Comet is running and is the frontmost application
- User has multiple Comet windows open (e.g., YouTube, ChatGPT)
- YouTube window is currently in focus (frontmost Comet window)
- ChatGPT window exists but is in the background

**User Action:**
- User triggers the Raycast command

**Expected Behavior:**
- YouTube disappears from view
- ChatGPT window appears in focus
- User can immediately continue their conversation

**Final State:**
- User is viewing their ChatGPT conversation
- YouTube window is still open in the background
- User can toggle back to YouTube later

**CRITICAL:** Since the user is already in Comet but in a different window, the toggle switches them to ChatGPT (not hiding it).

---

### Journey 5: ChatGPT Window Exists, User Is In Different App
**Initial State:**
- Comet is running but not frontmost
- ChatGPT window exists in Comet
- User is in a different application (e.g., Cursor)
- Another Comet window (e.g., YouTube) might be in front of ChatGPT

**User Action:**
- User triggers the Raycast command

**Expected Behavior:**
- Comet becomes the active application
- ChatGPT window appears in focus
- User can immediately continue their conversation

**Final State:**
- User is viewing their ChatGPT conversation
- Previous conversation state is preserved
- Other Comet windows (if any) remain in the background

---

### Journey 6: No ChatGPT Window, But Comet Is Running
**Initial State:**
- Comet is running (with other windows like YouTube open)
- No ChatGPT window exists
- User might be in Comet or in a different app

**User Action:**
- User triggers the Raycast command

**Expected Behavior:**
- A new ChatGPT window opens
- ChatGPT appears in focus
- User can start a new conversation

**Final State:**
- User is viewing ChatGPT
- Other Comet windows (e.g., YouTube) remain open in the background
- User can switch between windows

---

## Toggle Behavior Summary

The toggle works differently depending on the current state:

### When to Show ChatGPT
- If no ChatGPT window exists → Open new one
- If ChatGPT exists but is hidden → Show it
- If ChatGPT exists but user is in different window/app → Switch to it

### When to Hide ChatGPT  
- If ChatGPT is currently in focus:
  - **With other Comet windows:** Return to previous Comet window
  - **As only Comet window:** Hide entire Comet app

### Decision Flow

```
Does ChatGPT window exist?
├─ NO  → User sees new ChatGPT window open
└─ YES → Is user currently viewing ChatGPT?
          ├─ NO  → User switches to ChatGPT window
          └─ YES → Are there other Comet windows open?
                   ├─ YES → User returns to previous Comet window
                   └─ NO  → Comet hides, user returns to previous app
```

## Edge Cases

### Multiple ChatGPT Windows
If multiple ChatGPT windows somehow exist:
- Toggle works with the first one found
- No additional ChatGPT windows are created

### Rapid Toggling
If user triggers the script multiple times quickly:
- No duplicate ChatGPT windows are created
- Each toggle responds to the current visible state

## Success Criteria

A correct implementation will:
1. ✅ Never create duplicate ChatGPT windows
2. ✅ Find ChatGPT windows even when hidden
3. ✅ Keep ChatGPT window open (never close it) so user can quickly toggle back
4. ✅ When ChatGPT is in focus with other Comet windows: bring the next Comet window to front
5. ✅ When ChatGPT is the only Comet window: hide entire app as fallback
6. ✅ Bring ChatGPT to front when user is in a different Comet window
7. ✅ Bring ChatGPT to front when Comet is hidden
8. ✅ Create a new ChatGPT window only when none exists
9. ✅ Execute quickly (< 1 second response time)
10. ✅ Preserve ChatGPT conversation state across toggles


#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title ChatGPT Toggle (Swift)
// @raycast.mode fullOutput

// Optional parameters:
// @raycast.icon 🤖

// Documentation:
// @raycast.author Anders Bekkevard

import AppKit
import Foundation

let workspace = NSWorkspace.shared

// Find Comet app
let cometApps = workspace.runningApplications.filter { app in
    if let bundleId = app.bundleIdentifier, bundleId.contains("Comet") {
        return true
    }
    if let localizedName = app.localizedName, localizedName == "Comet" {
        return true
    }
    return false
}

// Get all windows (including hidden ones)
let allWindows = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

// Get visible windows only (to check what's frontmost)
let visibleWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

// Find ChatGPT window (in all windows, including hidden)
let chatGPTWindow = allWindows.first { window in
    if let owner = window[kCGWindowOwnerName as String] as? String,
       let title = window[kCGWindowName as String] as? String,
       owner == "Comet" && (title.localizedCaseInsensitiveContains("chatgpt") || title.localizedCaseInsensitiveContains("chat.openai.com")) {
        return true
    }
    return false
}

// Find the frontmost Comet window (only in visible windows)
let frontmostCometWindow = visibleWindows.first { window in
    if let owner = window[kCGWindowOwnerName as String] as? String,
       let title = window[kCGWindowName as String] as? String,
       !title.isEmpty,
       owner == "Comet" {
        return true
    }
    return false
}

let frontmostCometTitle = frontmostCometWindow?[kCGWindowName as String] as? String ?? "(none)"

// Check if the frontmost Comet window is a ChatGPT window
let isChatGPTFrontmost = frontmostCometWindow != nil && 
                         (frontmostCometTitle.localizedCaseInsensitiveContains("chatgpt") || 
                          frontmostCometTitle.localizedCaseInsensitiveContains("chat.openai.com"))

if chatGPTWindow != nil, let comet = cometApps.first {
    // ChatGPT window exists
    let frontmostApp = workspace.frontmostApplication
    let isCometFrontmost = frontmostApp?.bundleIdentifier == comet.bundleIdentifier
    
    if isCometFrontmost && isChatGPTFrontmost {
        // ChatGPT window is in focus, bring the next window to front
        let script = """
        tell application "Comet"
            set chatgptWindowIndex to -1
            set windowCount to count of windows
            
            -- Find the ChatGPT window index
            repeat with i from 1 to windowCount
                set w to window i
                set windowTitle to name of w
                if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" then
                    set chatgptWindowIndex to i
                    exit repeat
                end if
            end repeat
            
            -- If we found ChatGPT and there's another window
            if chatgptWindowIndex is not -1 and windowCount > 1 then
                -- Find the next window (wrapping around if needed)
                set nextWindowIndex to chatgptWindowIndex + 1
                if nextWindowIndex > windowCount then
                    set nextWindowIndex to 1
                end if
                
                -- If the next window IS the ChatGPT window (only 1 window), do nothing
                if nextWindowIndex is not chatgptWindowIndex then
                    set index of window nextWindowIndex to 1
                end if
            end if
        end tell
        """
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("⚠️ AppleScript error: \\(error)")
        }
    } else {
        // ChatGPT window exists but not in focus, bring it to front using AppleScript
        let script = """
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
        
        let appleScript = NSAppleScript(source: script)
        var error: NSDictionary?
        appleScript?.executeAndReturnError(&error)
        
        if let error = error {
            print("⚠️ AppleScript error: \\(error)")
        }
    }
} else {
    // No ChatGPT window found, launch one
    let task = Process()
    task.launchPath = "/Applications/Comet.app/Contents/MacOS/Comet"
    task.arguments = ["--app=https://chatgpt.com"]
    try? task.run()
}

exit(0)


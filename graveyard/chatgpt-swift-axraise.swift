#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title ChatGPT Toggle (Swift AXRaise)
// @raycast.mode fullOutput

// Optional parameters:
// @raycast.icon 🤖

// Documentation:
// @raycast.author Anders Bekkevard

import AppKit
import Foundation

// Start timing
let startTime = Date()
print("⏱️ [Swift AXRaise] Starting...")

let workspace = NSWorkspace.shared

// Check if Comet is running
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

// Find ChatGPT window
let chatGPTWindow = allWindows.first { window in
    if let owner = window[kCGWindowOwnerName as String] as? String,
       let title = window[kCGWindowName as String] as? String,
       owner == "Comet" && (title.localizedCaseInsensitiveContains("chatgpt") || title.localizedCaseInsensitiveContains("chat.openai.com")) {
        return true
    }
    return false
}

if chatGPTWindow == nil {
    // No ChatGPT window found, launch one
    print("🚀 No ChatGPT window found - launching new one")
    let task = Process()
    task.launchPath = "/Applications/Comet.app/Contents/MacOS/Comet"
    task.arguments = ["--app=https://chatgpt.com"]
    try? task.run()
    
    let elapsedTime = Date().timeIntervalSince(startTime)
    print("⏱️ [Swift AXRaise] Completed in \(String(format: "%.3f", elapsedTime)) seconds")
    exit(0)
}

// ChatGPT window exists - check if it's the frontmost window of ALL apps
let visibleWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

let frontmostWindow = visibleWindows.first { window in
    if let title = window[kCGWindowName as String] as? String,
       !title.isEmpty {
        return true
    }
    return false
}

let frontmostTitle = frontmostWindow?[kCGWindowName as String] as? String ?? ""
let isChatGPTFrontmost = frontmostTitle.localizedCaseInsensitiveContains("chatgpt") || frontmostTitle.localizedCaseInsensitiveContains("chat.openai.com")

print("🔍 Frontmost window: \"\(frontmostTitle)\"")
print("✅ Is ChatGPT frontmost: \(isChatGPTFrontmost)")

// Use AppleScript for window manipulation
if isChatGPTFrontmost {
    // ChatGPT is frontmost - push it all the way to the back
    print("🙈 Pushing ChatGPT to back")
    let script = """
    tell application "Comet"
        repeat with w in windows
            set windowTitle to name of w
            if windowTitle contains "ChatGPT" or windowTitle contains "chatgpt" or windowTitle contains "chat.openai.com" then
                -- Push to the very back
                set index of w to (count of windows)
                exit repeat
            end if
        end repeat
    end tell
    """
    
    let appleScript = NSAppleScript(source: script)
    var error: NSDictionary?
    appleScript?.executeAndReturnError(&error)
    
    if let error = error {
        print("⚠️ AppleScript error: \(error)")
    }
} else {
    // ChatGPT is not frontmost - bring it to front
    print("👁️ Activating Comet and bringing ChatGPT to front")
    let script = """
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
    """
    
    let appleScript = NSAppleScript(source: script)
    var error: NSDictionary?
    appleScript?.executeAndReturnError(&error)
    
    if let error = error {
        print("⚠️ AppleScript error: \(error)")
    }
}

let elapsedTime = Date().timeIntervalSince(startTime)
print("⏱️ [Swift AXRaise] Completed in \(String(format: "%.3f", elapsedTime)) seconds")

exit(0)


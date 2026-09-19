#!/usr/bin/swift

import ApplicationServices
import AppKit
import Foundation

private let betaBundleID = "com.raycast-x.macos"
private let targetLanguages = Set(["English", "Norwegian"])
private var raycastApplicationElement: AXUIElement?

private func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

private func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
        return nil
    }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: CFString) -> String? {
    attribute(element, name) as? String
}

private func elementsAttribute(_ element: AXUIElement, _ name: CFString) -> [AXUIElement] {
    attribute(element, name) as? [AXUIElement] ?? []
}

private func parent(of element: AXUIElement) -> AXUIElement? {
    attribute(element, kAXParentAttribute as CFString) as! AXUIElement?
}

private func ancestor(of element: AXUIElement, withRole role: String) -> AXUIElement? {
    var current = parent(of: element)
    while let candidate = current {
        if stringAttribute(candidate, kAXRoleAttribute as CFString) == role {
            return candidate
        }
        current = parent(of: candidate)
    }
    return nil
}

private func descendants(of root: AXUIElement, limit: Int = 2_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var queue = elementsAttribute(root, kAXChildrenAttribute as CFString)
    var index = 0

    while index < queue.count, result.count < limit {
        let element = queue[index]
        index += 1
        result.append(element)
        queue.append(contentsOf: elementsAttribute(element, kAXChildrenAttribute as CFString))
    }

    return result
}

private func wait<T>(seconds: TimeInterval = 5, for value: () -> T?) -> T? {
    let deadline = Date().addingTimeInterval(seconds)
    repeat {
        if let result = value() {
            return result
        }
        Thread.sleep(forTimeInterval: 0.1)
    } while Date() < deadline
    return nil
}

private func frame(of element: AXUIElement) -> CGRect? {
    guard
        let positionValue = attribute(element, kAXPositionAttribute as CFString),
        let sizeValue = attribute(element, kAXSizeAttribute as CFString)
    else {
        return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

private func focusRaycastBeta() {
    let source = #"tell application "System Events" to tell process "Raycast Beta" to set frontmost to true"#
    var error: NSDictionary?
    NSAppleScript(source: source)?.executeAndReturnError(&error)
    if let error {
        fail("Could not focus Raycast Beta: \(error)")
    }
}

private func click(_ element: AXUIElement) -> Bool {
    focusRaycastBeta()
    if let application = raycastApplicationElement {
        AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let frame = frame(of: element), frame.width > 1, frame.height > 1 else {
        return false
    }

    let center = CGPoint(x: frame.midX, y: frame.midY)
    guard
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)
    else {
        return false
    }
    CGWarpMouseCursorPosition(center)
    Thread.sleep(forTimeInterval: 0.05)
    down.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.03)
    up.post(tap: .cghidEventTap)
    return true
}

private func scrollIntoView(_ element: AXUIElement, within window: AXUIElement) -> Bool {
    guard let windowFrame = frame(of: window) else {
        return false
    }
    let visibleFrame = windowFrame.insetBy(dx: 30, dy: 45)
    func isVisible(_ elementFrame: CGRect) -> Bool {
        elementFrame.minY >= visibleFrame.minY
            && elementFrame.maxY <= visibleFrame.maxY
            && elementFrame.maxX > windowFrame.minX
            && elementFrame.minX < windowFrame.maxX
    }

    if AXUIElementPerformAction(element, "AXScrollToVisible" as CFString) == .success {
        if wait(seconds: 2, for: { () -> Bool? in
            guard let elementFrame = frame(of: element) else { return nil }
            return isVisible(elementFrame) ? true : nil
        }) != nil {
            return true
        }
    }

    for _ in 0..<8 {
        guard let elementFrame = frame(of: element) else {
            return false
        }
        if isVisible(elementFrame) {
            return true
        }

        let delta: Int32 = elementFrame.maxY > visibleFrame.maxY ? 240 : -240
        let point = CGPoint(
            x: min(max(elementFrame.midX, visibleFrame.minX), visibleFrame.maxX),
            y: visibleFrame.midY
        )
        CGWarpMouseCursorPosition(point)
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else {
            return false
        }
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.15)
    }

    return frame(of: element).map(isVisible) ?? false
}

private func sendCommandComma() {
    guard
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 43, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 43, keyDown: false)
    else {
        fail("Could not create the Settings keyboard shortcut")
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

private func launchRaycastBeta() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-b", betaBundleID]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("Could not launch Raycast Beta: \(error.localizedDescription)")
    }
}

guard let target = CommandLine.arguments.dropFirst().first, targetLanguages.contains(target) else {
    fail("Usage: set-raycast-beta-dictation-language.swift English|Norwegian")
}

guard AXIsProcessTrusted() else {
    fail("Raycast Beta needs Accessibility permission to change its Dictation language")
}

if NSRunningApplication.runningApplications(withBundleIdentifier: betaBundleID).isEmpty {
    launchRaycastBeta()
}

guard let raycastBeta = wait(seconds: 8, for: {
    NSRunningApplication.runningApplications(withBundleIdentifier: betaBundleID).first
}) else {
    fail("Raycast Beta did not start")
}

let application = AXUIElementCreateApplication(raycastBeta.processIdentifier)
raycastApplicationElement = application
focusRaycastBeta()
AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
Thread.sleep(forTimeInterval: 0.2)
let existingSettingsWindow = elementsAttribute(application, kAXWindowsAttribute as CFString).first(where: {
    stringAttribute($0, kAXTitleAttribute as CFString) == "Settings"
})
if existingSettingsWindow == nil {
    sendCommandComma()
}

guard let settingsWindow = existingSettingsWindow ?? wait(seconds: 5, for: {
    elementsAttribute(application, kAXWindowsAttribute as CFString).first(where: {
        stringAttribute($0, kAXTitleAttribute as CFString) == "Settings"
    })
}) else {
    fail("Raycast Beta Settings did not open")
}

func isDictationPage() -> Bool {
    descendants(of: settingsWindow).contains(where: {
        stringAttribute($0, kAXRoleAttribute as CFString) == "AXHeading"
            && (stringAttribute($0, kAXTitleAttribute as CFString) == "Dictation"
                || stringAttribute($0, kAXValueAttribute as CFString) == "Dictation")
    })
}

if !isDictationPage() {
    guard let settingsSearchField = descendants(of: settingsWindow).first(where: {
        stringAttribute($0, kAXRoleAttribute as CFString) == kAXTextFieldRole as String
            && stringAttribute($0, kAXTitleAttribute as CFString) == "Search settings"
    }) else {
        fail("Could not search Raycast Beta Settings")
    }
    AXUIElementSetAttributeValue(settingsSearchField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    guard AXUIElementSetAttributeValue(settingsSearchField, kAXValueAttribute as CFString, "Dictation" as CFString) == .success else {
        fail("Could not search for Dictation in Raycast Beta Settings")
    }

    guard let dictationResult = wait(for: {
        descendants(of: settingsWindow).first(where: {
            stringAttribute($0, kAXRoleAttribute as CFString) == kAXButtonRole as String
                && stringAttribute($0, kAXTitleAttribute as CFString)?.hasPrefix("Dictation") == true
                && (frame(of: $0)?.width ?? 0) > 1
        })
    }) else {
        fail("Could not open Raycast Beta Dictation settings")
    }

    guard click(dictationResult) else {
        fail("Could not activate Raycast Beta Dictation settings")
    }
    guard wait(seconds: 5, for: { isDictationPage() ? true : nil }) != nil else {
        fail("Raycast Beta did not navigate to Dictation settings")
    }
}

guard let languageButton = wait(for: {
    descendants(of: settingsWindow).first(where: {
        stringAttribute($0, kAXRoleAttribute as CFString) == kAXButtonRole as String
            && stringAttribute($0, kAXTitleAttribute as CFString) == "Language"
    })
}) else {
    fail("Could not find the Dictation language picker")
}
guard scrollIntoView(languageButton, within: settingsWindow) else {
    fail("Could not bring the Dictation language picker into view")
}
guard click(languageButton) else {
    fail("Could not open the Dictation language picker")
}

guard let searchField = wait(for: {
    descendants(of: application).first(where: {
        stringAttribute($0, kAXRoleAttribute as CFString) == kAXTextFieldRole as String
            && stringAttribute($0, kAXPlaceholderValueAttribute as CFString) == "Search…"
    })
}) else {
    fail("The Dictation language picker did not open")
}

guard let picker = ancestor(of: searchField, withRole: "AXWebArea") else {
    fail("Could not identify the Dictation language picker")
}

AXUIElementSetAttributeValue(searchField, kAXFocusedAttribute as CFString, kCFBooleanTrue)
guard AXUIElementSetAttributeValue(searchField, kAXValueAttribute as CFString, target as CFString) == .success else {
    fail("Could not search for \(target) in the Dictation language picker")
}

guard let result = wait(for: {
    descendants(of: picker).first(where: {
        stringAttribute($0, kAXRoleAttribute as CFString) == kAXStaticTextRole as String
            && stringAttribute($0, kAXValueAttribute as CFString) == target
    })
}), let resultRow = parent(of: result), click(resultRow) else {
    fail("Could not select \(target) in the Dictation language picker")
}

guard wait(seconds: 3, for: {
    let pickerIsOpen = descendants(of: application).contains(where: {
        stringAttribute($0, kAXRoleAttribute as CFString) == kAXTextFieldRole as String
            && stringAttribute($0, kAXPlaceholderValueAttribute as CFString) == "Search…"
    })
    return pickerIsOpen ? nil : true
}) != nil else {
    fail("Raycast Beta did not confirm the \(target) language selection")
}

if let closeButton = attribute(settingsWindow, kAXCloseButtonAttribute as CFString) as! AXUIElement? {
    AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
}
Thread.sleep(forTimeInterval: 0.1)
raycastBeta.hide()

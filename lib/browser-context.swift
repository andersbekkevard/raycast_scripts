import AppKit
import CoreGraphics

let workspace = NSWorkspace.shared
let running = workspace.runningApplications.filter { $0.activationPolicy == .regular }
var front = workspace.frontmostApplication?.localizedName ?? ""
if front == "Raycast" || front == "Raycast Beta" {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in windows {
        guard (window[kCGWindowLayer as String] as? Int) == 0,
              let pid = window[kCGWindowOwnerPID as String] as? Int32,
              let app = running.first(where: { $0.processIdentifier == pid }),
              let name = app.localizedName,
              name != "Raycast", name != "Raycast Beta" else { continue }
        front = name
        break
    }
}
let value: [String: Any] = ["front": front, "running": running.compactMap { $0.localizedName }]
print(String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)!)

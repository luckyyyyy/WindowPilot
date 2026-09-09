import Foundation
import CoreGraphics

/// Separate document/settings windows from popovers, overlays and attached sheets.
enum WindowPolicy {
    struct Facts {
        var role = "AXWindow"
        var subrole = "AXStandardWindow"
        var modal = false
        var closable = true
        var regularApp = true
        var matchingLayers: [Int] = []
    }

    static func accepts(_ f: Facts) -> Bool {
        guard f.role == "AXWindow" else { return false }
        if !f.matchingLayers.isEmpty && f.matchingLayers.allSatisfy({ $0 > 8 }) { return false }
        let dialog = f.subrole == "AXDialog" || f.subrole == "AXSystemDialog" || f.modal
        if dialog { return f.closable || f.modal }
        // A standard AX role alone is not enough: overlay panels can claim it too.
        if !f.matchingLayers.isEmpty && !f.matchingLayers.contains(0) { return false }
        if f.subrole == "AXStandardWindow" { return f.regularApp || f.closable }
        // Some cross-platform apps do not supply a subrole. Require a real normal-layer window.
        return (f.subrole.isEmpty || f.subrole == "AXUnknown")
            && f.closable && f.matchingLayers.contains(0)
    }

    /// AX can expose only helper panels even when a regular app is running.
    /// Decide after filtering so those panels cannot suppress its application row.
    static func needsApplicationFallback(regularApp: Bool, acceptedWindowCount: Int) -> Bool {
        regularApp && acceptedWindowCount == 0
    }

    static func title(axTitle: String, document: String, serverTitle: String, appName: String) -> String {
        let title = axTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let url = URL(string: document), url.isFileURL, !url.lastPathComponent.isEmpty { return url.lastPathComponent }
        let server = serverTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return server.isEmpty ? appName : server
    }
}

struct ServerWindow {
    let pid: pid_t
    let frame: CGRect
    let layer: Int
    let title: String

    static func snapshot() -> [ServerWindow] {
        guard let records = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return records.compactMap { record in
            guard let pid = record[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = record[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let layer = record[kCGWindowLayer as String] as? Int else { return nil }
            // Names are optional without Screen Recording permission. We never request it.
            return ServerWindow(pid: pid, frame: frame, layer: layer, title: record[kCGWindowName as String] as? String ?? "")
        }
    }

    func matches(_ frame: CGRect) -> Bool {
        abs(self.frame.minX - frame.minX) < 3 && abs(self.frame.minY - frame.minY) < 3
            && abs(self.frame.width - frame.width) < 3 && abs(self.frame.height - frame.height) < 3
    }
}

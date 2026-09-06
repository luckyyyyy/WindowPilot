import AppKit
import SwiftUI

/// Preview the shipping row with sample titles, without Accessibility or real window actions.
private struct PreviewRows: View {
    @State private var selectedIndex = 1
    private let samples = [
        ("Finder", "项目文件"),
        ("WindowPilot", "键盘选中 · 主色高亮"),
        ("Safari", "鼠标悬停 · 中性灰色"),
        ("Notes", "移出鼠标后恢复背景")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                let item = WindowItem(id: String(index), pid: -1, appName: sample.0,
                    bundleID: "preview", title: sample.1, minimized: false, hidden: false,
                    isAppOnly: false, focused: false, lastUsed: 0)
                SwitcherRow(result: WindowSearch.results([item], query: "")[0],
                            icon: NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)!,
                            selected: selectedIndex == index, rowHeight: 28) {
                    selectedIndex = index
                }
            }
        }
        .padding(8)
        .frame(width: 640)
    }
}

/// A safe, contrasting desktop substitute for inspecting behind-window blur.
private struct PreviewBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue, .purple, .orange], startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 75) {
                ForEach(0..<6) { _ in
                    Rectangle().fill(.white.opacity(0.55)).frame(width: 36)
                }
            }
        }
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@main
private enum SwitcherPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: CommandLine.arguments.contains("--light") ? .aqua : .darkAqua)
        let backdrop = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 300),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        backdrop.title = "WindowPilot Glass Preview · Sample Backdrop"
        backdrop.contentView = NSHostingView(rootView: PreviewBackdrop())
        backdrop.center()
        backdrop.makeKeyAndOrderFront(nil)
        let window = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 128),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.level = .popUpMenu
        window.acceptsMouseMovedEvents = true
        window.title = "WindowPilot Glass Preview"
        window.contentView = SwitcherSurface(rootView: PreviewRows())
        window.setFrameOrigin(NSPoint(x: backdrop.frame.midX - 320, y: backdrop.frame.minY + 86))
        window.makeKeyAndOrderFront(nil)
        app.activate()
        app.run()
    }
}

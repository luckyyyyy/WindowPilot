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
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.93), in: .rect(cornerRadius: 10))
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

@main
private enum SwitcherPreview {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.appearance = NSAppearance(named: CommandLine.arguments.contains("--light") ? .aqua : .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 128),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.acceptsMouseMovedEvents = true
        window.title = "WindowPilot Hover Preview"
        window.contentView = NSHostingView(rootView: PreviewRows())
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate()
        app.run()
    }
}

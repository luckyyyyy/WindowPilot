import AppKit
@MainActor final class Fixture: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var confirmActions = ProcessInfo.processInfo.arguments.contains("--confirm-actions")
    var confirming = false
    var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit WindowPilot Test", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem); NSApp.mainMenu = menu
        var titles = ["WindowPilot Test · Document", "WindowPilot Test · 设置"]
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--window-count"), args.indices.contains(index + 1),
           let count = Int(args[index + 1]), count > 2 {
            titles += (3...min(count, 100)).map { "WindowPilot Test · Document \($0)" }
        }
        for (i, title) in titles.enumerated() {
            let w = i == 0
              ? NSWindow(contentRect: NSRect(x: 140, y: 160, width: 500, height: 300), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
              : NSPanel(contentRect: NSRect(x: 280, y: 280, width: 420, height: 240), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.delegate = self
            w.title = title
            w.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: i == 0 ? "Test document — safe to minimize" : "独立设置窗口 · NSPanel")
            label.frame = NSRect(x: 35, y: 100, width: 360, height: 40)
            w.contentView?.addSubview(label)
            let rename = NSButton(title: "更改测试文档标题", target: self, action: #selector(renameDocument))
            rename.frame = NSRect(x: 35, y: 45, width: 200, height: 30)
            w.contentView?.addSubview(rename)
            w.makeKeyAndOrderFront(nil)
            windows.append(w)
        }
        NSApp.activate()
    }
    @objc func renameDocument() {
        windows.first?.title = "WindowPilot Test · Document Updated"
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard confirmActions else { return true }
        guard !confirming else { return false }
        confirming = true
        let alert = NSAlert()
        alert.messageText = "测试：未保存的窗口"
        alert.informativeText = "这是可丢弃的测试窗口。取消应保留窗口。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "关闭测试窗口")
        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            self?.confirming = false
            if response == .alertSecondButtonReturn { sender?.close() }
        }
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard confirmActions, let window = windows.first(where: { $0.isVisible }) else { return .terminateNow }
        guard !confirming else { return .terminateCancel }
        confirming = true
        let alert = NSAlert()
        alert.messageText = "测试：退出前确认"
        alert.informativeText = "取消应保留测试应用，退出才结束测试进程。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "退出测试应用")
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.confirming = false
            NSApp.reply(toApplicationShouldTerminate: response == .alertSecondButtonReturn)
        }
        return .terminateLater
    }
}
let app = NSApplication.shared
let delegate = Fixture()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

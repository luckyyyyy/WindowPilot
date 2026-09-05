import AppKit
import SwiftUI

@main
struct WindowPilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra("WindowPilot", systemImage: "rectangle.on.rectangle") {
            StatusMenu(controller: .shared)
        }
        .commands {
            CommandGroup(before: .windowList) {
                Button("打开窗口切换器") { SwitcherController.shared.begin() }
                Divider()
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.windowpilot.app").count > 1 {
            NSApp.terminate(nil); return
        }
        if let path = Bundle.main.path(forResource: "WindowPilotIcon", ofType: "icns"), let icon = NSImage(contentsOfFile: path) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.accessory)
        SwitcherController.shared.start()
    }
    func applicationWillTerminate(_ notification: Notification) { SwitcherController.shared.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SwitcherController.shared.showSettings(); return true
    }
}

struct StatusMenu: View {
    @Bindable var controller: SwitcherController
    var body: some View {
        Text("WindowPilot")
        Text(controller.statusText)
        Divider()
        Button("打开窗口切换器") { controller.begin() }.disabled(!controller.keyboardReady)
        Button("设置…") { controller.showSettings() }.keyboardShortcut(",")
        Toggle("启用 ⌘Tab", isOn: Binding(get: { controller.preferences.enabled }, set: { controller.setEnabled($0) }))
        Divider()
        Button("退出 WindowPilot") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

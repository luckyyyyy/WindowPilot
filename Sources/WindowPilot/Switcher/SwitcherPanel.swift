import AppKit
import SwiftUI

@MainActor
final class SwitcherPanel: NSPanel {
    private var presentationBounds = NSRect(x: 0, y: 0, width: 1440, height: 900)
    init(controller: SwitcherController) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        acceptsMouseMovedEvents = true
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: SwitcherView(controller: controller))
        setAccessibilityLabel("WindowPilot 窗口切换器")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(layout: SwitcherLayout) {
        let target = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        presentationBounds = target?.visibleFrame ?? presentationBounds
        setFrame(layout.frame(in: presentationBounds), display: true)
        makeKeyAndOrderFront(nil)
    }

    func resize(layout: SwitcherLayout) {
        // Keep the panel on its current display even if the pointer moves away.
        presentationBounds = screen?.visibleFrame ?? presentationBounds
        let next = layout.frame(in: presentationBounds)
        if frame != next { setFrame(next, display: true) }
    }
}

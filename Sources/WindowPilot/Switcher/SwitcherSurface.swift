import AppKit
import SwiftUI

/// AppKit owns the backdrop and glass edge, including appearance and accessibility changes.
@MainActor
final class SwitcherSurface<Content: View>: NSGlassEffectView {
    init(rootView: Content) {
        super.init(frame: .zero)
        style = .regular
        cornerRadius = 10

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.sizingOptions = []
        contentView = hostingView
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

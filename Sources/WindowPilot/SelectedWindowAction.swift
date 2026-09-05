import AppKit

enum SelectedWindowAction: Sendable {
    case closeWindow, quitApplication

    static func match(_ event: CGEvent) -> Self? {
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn])
        guard modifiers == .maskCommand else { return nil }
        // Respect the active keyboard layout rather than assuming US physical keys.
        switch NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased() {
        case "w": return .closeWindow
        case "q": return .quitApplication
        default: return nil
        }
    }
}

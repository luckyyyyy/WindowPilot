import AppKit

enum SelectedWindowAction: Sendable {
    case closeWindow, quitApplication

    static func match(_ event: CGEvent, configuration: ShortcutConfiguration = .init(), ignoring: CGEventFlags = []) -> Self? {
        if configuration.closeWindow.matches(event, ignoring: ignoring) { return .closeWindow }
        if configuration.quitApplication.matches(event, ignoring: ignoring) { return .quitApplication }
        return nil
    }
}

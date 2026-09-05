import Foundation
import Testing
@testable import WindowPilot

@Suite @MainActor
struct PreferencesTests {
    @Test func compactRowsAreDefaultAndExplicitChoicePersists() throws {
        let suite = "WindowPilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.compact)
        preferences.compact = false
        #expect(!Preferences(defaults: defaults).compact)
        preferences.compact = true
        #expect(Preferences(defaults: defaults).compact)
    }
}

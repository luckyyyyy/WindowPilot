import Foundation
import Testing
@testable import WindowPilot

@Suite @MainActor
struct PreferencesTests {
    @Test func appearanceDefaultsToSystemAndPersistsEachChoice() throws {
        let suite = "WindowPilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "compact")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.appearance == .system)
        for appearance in [AppearancePreference.dark, .light, .system] {
            preferences.appearance = appearance
            let reloaded = Preferences(defaults: defaults)
            #expect(reloaded.appearance == appearance)
            #expect(!reloaded.compact)
        }
        defaults.set("invalid", forKey: "appearance")
        #expect(Preferences(defaults: defaults).appearance == .system)
    }

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

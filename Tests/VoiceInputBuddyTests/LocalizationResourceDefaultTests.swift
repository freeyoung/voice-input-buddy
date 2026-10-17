import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Default localization resource lookup") @MainActor
struct LocalizationResourceDefaultTests {
    @Test func bareExecutableUsesResourcesAndLanguageChangesKeepOldSnapshotsStable() throws {
        let name = "locale-default-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalizationStore(settings: AppSettings(defaults: defaults))
        let key = SettingsSection.permissions.titleKey
        store.select(.english)
        let english = store.text(key)
        let snapshot = store.snapshot
        store.select(.simplifiedChinese)
        let chinese = store.text(key)
        #expect(english != key)
        #expect(chinese != key)
        #expect(english != chinese)
        #expect(snapshot.text(key) == english)
        #expect(LocalizationSnapshot(language: .english).text(key) == english)
    }
}

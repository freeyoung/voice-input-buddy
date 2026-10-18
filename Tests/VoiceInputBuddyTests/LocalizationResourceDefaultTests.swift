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

    @Test func rc003VoiceExtensionTestResolvesInBothLanguages() throws {
        let name = "locale-rc003-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = LocalizationStore(settings: AppSettings(defaults: defaults))
        let key = "about.preferences.rc003_voice_extension_test"
        store.select(.english)
        let english = store.text(key)
        store.select(.simplifiedChinese)
        let chinese = store.text(key)
        #expect(english == "Test extended voice feature")
        #expect(chinese == "测试长时间语音功能")
    }
}

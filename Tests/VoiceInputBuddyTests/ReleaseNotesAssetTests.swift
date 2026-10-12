import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Published update note assets")
struct ReleaseNotesAssetTests {
    @Test func localizedAssetsMatchReleasePackageDirectory() throws {
        let package = try #require(URL(string: "https://github.com/zfdang/voice-input-buddy/releases/download/v26-10-12.036/Voice_Input_Buddy_v26-10-12.036_macOS_intel.pkg"))
        for (locale, language) in [("zh_CN", "zh"), ("en_US", "en")] {
            let url = try #require(UpdateReleaseNotes.assetURL(for: package, displayVersion: "v26-10-12.036", localeIdentifier: locale))
            #expect(url.lastPathComponent == "Voice_Input_Buddy_v26-10-12.036.\(language).txt")
            #expect(url.deletingLastPathComponent() == package.deletingLastPathComponent())
        }
        #expect(UpdateReleaseNotes.assetURL(for: package, displayVersion: "../escape", localeIdentifier: "en") == nil)
    }
}

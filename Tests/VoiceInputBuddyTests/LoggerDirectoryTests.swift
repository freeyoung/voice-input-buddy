import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Log directory selection")
struct LoggerDirectoryTests {
    @Test func missingLibraryDirectoryUsesPrivateHomeLocationWithoutIndexing() {
        let home = URL(fileURLWithPath: "/private/var/test-user", isDirectory: true)
        #expect(AppLogger.defaultLogDirectory(libraries: [], home: home).path == "/private/var/test-user/Library/Logs/VoiceInputBuddy")
        let library = URL(fileURLWithPath: "/some/Library", isDirectory: true)
        #expect(AppLogger.defaultLogDirectory(libraries: [library], home: home).path == "/some/Library/Logs/VoiceInputBuddy")
    }
}

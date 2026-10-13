import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Local structured diagnostics")
struct LocalDiagnosticTests {
    @Test func structuredEventsAreWrittenToTheLocalLog() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("runtime.log")
        let logger = AppLogger(logURL: log, reportFailure: { _ in })
        let event = try #require(PublicDiagnosticEvent(component: "settings", action: "load",
            phase: "completed", result: "loaded", reason: "remote_profiles", source: "app"))
        logger.record(event)
        logger.flush()
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains(event.canonicalLine))
        #expect(PublicDiagnosticEvent.parse(event.canonicalLine) == event)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(files == [".voiceinputbuddy-diagnostic-log.lock", "runtime.log"])
    }

    @Test func disabledLoggingDoesNotCreateAnEventFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("runtime.log")
        let logger = AppLogger(logURL: log, reportFailure: { _ in }, isEnabled: false)
        let event = try #require(PublicDiagnosticEvent(component: "settings", action: "load",
            phase: "completed", result: "loaded", reason: "remote_profiles", source: "app"))
        logger.record(event)
        logger.flush()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

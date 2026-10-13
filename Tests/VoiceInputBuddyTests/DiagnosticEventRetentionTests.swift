import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Local diagnostic event retention")
struct DiagnosticEventRetentionTests {
    private func event(reason: String = "button_mapping") throws -> PublicDiagnosticEvent {
        try #require(PublicDiagnosticEvent(component: "settings", action: "load",
            phase: "completed", result: "loaded", reason: reason, source: "app"))
    }
    private func run(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("events.json"))
    }

    @Test func capacitySurvivesReloadAndAcknowledgementRemovesOnlyMatchingEvent() throws {
        try run { path in
            let first = try event()
            let second = try event()
            let third = try event()
            let unrelated = try event()
            let store = PublicDiagnosticEventStore(fileURL: path, capacity: 2)
            for value in [first, second, third] { try store.append(value) }
            #expect(store.pending() == [second, third])
            let reopened = PublicDiagnosticEventStore(fileURL: path, capacity: 2)
            try reopened.acknowledge([second, unrelated])
            #expect(reopened.pending() == [third])
            #expect(PublicDiagnosticEventStore(fileURL: path, capacity: 2).pending() == [third])
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test func expirationUsesInjectedClockAndIsAppliedAfterReload() throws {
        try run { path in
            var now = Date(timeIntervalSince1970: 1_000)
            let first = try event()
            let second = try event()
            let store = PublicDiagnosticEventStore(fileURL: path, ttl: 10, now: { now })
            try store.append(first)
            now = Date(timeIntervalSince1970: 1_004)
            try store.append(second)
            now = Date(timeIntervalSince1970: 1_010)
            #expect(store.pending() == [first, second])
            now = Date(timeIntervalSince1970: 1_011)
            #expect(store.pending() == [second])
            #expect(PublicDiagnosticEventStore(fileURL: path, ttl: 10, now: { now }).pending() == [second])
            now = Date(timeIntervalSince1970: 1_015)
            #expect(store.pending().isEmpty)
        }
    }

    @Test func invalidStorageAndUnapprovedEventsDoNotBecomePendingRecords() throws {
        try run { path in
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("broken-json".utf8).write(to: path)
            let store = PublicDiagnosticEventStore(fileURL: path)
            #expect(store.pending().isEmpty)
            let unapproved = try event(reason: "unapproved_detail")
            #expect(!unapproved.isApprovedForUpload)
            try store.append(unapproved)
            #expect(store.pending().isEmpty)
            let approved = try event()
            #expect(approved.isApprovedForUpload)
            try store.append(approved)
            #expect(PublicDiagnosticEventStore(fileURL: path).pending() == [approved])
        }
    }
}

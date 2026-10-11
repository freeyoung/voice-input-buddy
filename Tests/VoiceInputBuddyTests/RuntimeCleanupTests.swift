import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Diagnostic log retention")
struct DiagnosticLogRetentionTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func sizeLimitStopsRepeatedFailureReports() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var failures: [String] = []
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let url = root.appendingPathComponent("voiceinputbuddy.app-test.rmlog")
        let logger = AppLogger(logURL: url, maximumFileSize: 512,
                               reportFailure: { failures.append($0) }, publicKeyDataProvider: { key })
        for _ in 0..<20 { logger.writeSynchronously(String(repeating: "x", count: 600), at: Date()) }
        #expect(failures == ["encrypted_log_size_limit_reached"])
        #expect(try Data(contentsOf: url).count <= 512)
    }

    @Test func missingKeyReportsOnceWithoutCreatingPlaintext() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var failures: [String] = []
        let url = root.appendingPathComponent("voiceinputbuddy.app-test.rmlog")
        let logger = AppLogger(logURL: url, reportFailure: { failures.append($0) }, publicKeyDataProvider: { nil })
        for _ in 0..<20 { logger.writeSynchronously("private text", at: Date()) }
        #expect(failures == ["encryption_public_key_missing"])
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func retentionKeepsNewestArchivesAndUnrelatedFiles() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("sayall.app-old.rmlog")
        let recent = root.appendingPathComponent("voiceinputbuddy.app-recent.rmlog")
        let unrelated = root.appendingPathComponent("user.rmlog")
        for url in [old, recent, unrelated] { try Data("archive".utf8).write(to: url) }
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: recent.path)
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let logger = AppLogger(logURL: root.appendingPathComponent("voiceinputbuddy.app-current.rmlog"),
                               archiveCount: 1, publicKeyDataProvider: { key })
        withExtendedLifetime(logger) {
            #expect(!FileManager.default.fileExists(atPath: old.path))
            #expect(FileManager.default.fileExists(atPath: recent.path))
            #expect(FileManager.default.fileExists(atPath: unrelated.path))
        }
    }

    @Test func retentionSkipsActiveSessionsAndSymbolicLinks() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let key = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let activeURL = root.appendingPathComponent("voiceinputbuddy.app-active.rmlog")
        let active = AppLogger(logURL: activeURL, publicKeyDataProvider: { key })
        let target = root.appendingPathComponent("user-data")
        try Data("untouched".utf8).write(to: target)
        let link = root.appendingPathComponent("voiceinputbuddy.app-link.rmlog")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let next = AppLogger(logURL: root.appendingPathComponent("voiceinputbuddy.app-next.rmlog"),
                             archiveCount: 0, publicKeyDataProvider: { key })
        let targetContents = try String(contentsOf: target, encoding: .utf8)
        let linkDestination = try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
        withExtendedLifetime((active, next)) {
            active.writeSynchronously("still active", at: Date())
            #expect(FileManager.default.fileExists(atPath: activeURL.path))
            #expect(targetContents == "untouched")
            #expect(linkDestination == target.path)
        }
    }
}

@Suite("Keyboard event filtering")
struct KeyboardEventFilteringTests {
    @Test func freshPhysicalKeyDownClearsStaleHeldState() throws {
        let suppressor = KeyboardEventSuppressor()
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 38, keyDown: true))
        suppressor.arm(nativeEvents: [.keyboard(keyCode: 38)], edge: .down)
        #expect(suppressor.handle(type: .keyDown, event: event))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(suppressor.handle(type: .keyDown, event: event))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        #expect(!suppressor.handle(type: .keyDown, event: event))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(!suppressor.handle(type: .keyDown, event: event))
    }

    @Test func injectedKeysDoNotConsumeRemoteSuppression() throws {
        let suppressor = KeyboardEventSuppressor()
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 38, keyDown: true))
        suppressor.arm(nativeEvents: [.keyboard(keyCode: 38)], edge: .down)
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardInjector.syntheticEventMarker)
        #expect(!suppressor.handle(type: .keyDown, event: event))
        let physical = try #require(CGEvent(keyboardEventSource: CGEventSource(stateID: .privateState), virtualKey: 38, keyDown: true))
        #expect(physical.getIntegerValueField(.eventSourceUserData) != KeyboardInjector.syntheticEventMarker)
        #expect(suppressor.handle(type: .keyDown, event: physical))
    }
}

@Suite("Product deep links")
struct ProductDeepLinkTests {
    @Test func registeredSchemeMatchesParser() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let types = try #require(plist["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = try #require(types.first?["CFBundleURLSchemes"] as? [String])
        let scheme = try #require(schemes.first)
        let url = try #require(URL(string: "\(scheme)://launch?source=vokie&status=ready"))
        let request = try #require(VoiceInputBuddyDeepLinkRequest.parse(url))
        #expect(request.source == "vokie")
        #expect(request.status == .ready)
    }

    @Test func rejectsOtherAppsAndAmbiguousParameters() throws {
        for value in ["sayall://launch", "voice-input-buddy://launch?status=ready&status=failed",
                      "voice-input-buddy://launch#fragment", "voice-input-buddy://other"] {
            #expect(VoiceInputBuddyDeepLinkRequest.parse(try #require(URL(string: value))) == nil)
        }
    }
}

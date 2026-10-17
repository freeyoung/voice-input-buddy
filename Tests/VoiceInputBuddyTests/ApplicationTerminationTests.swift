import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Application termination")
@MainActor
struct ApplicationTerminationTests {
    @Test func acceptedQuitClosesVoiceAdmissionBeforeRuntimeTeardown() throws {
        let name = UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: values))
        model.started = true
        defer { model.started = false }
        model.prepareForTermination()
        #expect(!model.canAcceptNewVoiceSession(from: .bluetooth))
        model.beginVoiceSessionIfNeeded()
        #expect(!model.isStreaming)
    }

    @Test func repeatedQuitAndReleaseCallbacksReplyExactlyOnce() {
        let coordinator = ApplicationTerminationCoordinator()
        var releases: [() -> Void] = []
        var replies = 0
        for _ in 0..<3 {
            coordinator.request(begin: { releases.append($0) }, reply: { replies += 1 })
        }
        #expect(coordinator.isTerminating)
        #expect(releases.count == 1)
        #expect(replies == 0)
        releases[0]()
        releases[0]()
        #expect(replies == 1)
    }
}

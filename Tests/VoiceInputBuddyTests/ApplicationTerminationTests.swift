import Testing
@testable import VoiceInputBuddy

@Suite("Application termination")
@MainActor
struct ApplicationTerminationTests {
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

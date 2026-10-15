import Testing
@testable import VoiceInputBuddy

@Suite("Voice playback capacity")
struct VoicePlaybackCapacityTests {
    @Test func burstAndDriftCannotExceedHalfASecond() {
        #expect(VoicePlaybackQueueCapacity.admits(pending: 0, incoming: 8_000))
        #expect(!VoicePlaybackQueueCapacity.admits(pending: 8_000, incoming: 1))
        #expect(!VoicePlaybackQueueCapacity.admits(pending: 0, incoming: Int.max))
        #expect(!VoicePlaybackQueueCapacity.admits(pending: Int.max, incoming: 320))
        #expect(!VoicePlaybackQueueCapacity.admits(pending: 0, incoming: 0))
        #expect(VoicePlaybackQueueCapacity.admits(pending: 7_680, incoming: 320))
        #expect(!VoicePlaybackQueueCapacity.admits(pending: 7_681, incoming: 320))
        // Playback makes room again without tearing down the engine/session.
        #expect(VoicePlaybackQueueCapacity.admits(pending: 7_360, incoming: 320))
    }
}

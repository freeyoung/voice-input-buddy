import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Voice delivery after asynchronous configuration")
struct VoiceDeliveryReadinessTests {
    private func attempt() -> VoiceAudioDeliveryDiagnostic {
        var value = VoiceAudioDeliveryDiagnostic(generation: 1, route: .virtualAudioDirect,
            sessionEnded: true, receivedSamples: 22_560)
        value.outputAtObservation = VirtualAudioOutputDiagnosticSnapshot(
            selectedDeviceKind: .buddyMic, actualDeviceKind: .buddyMic,
            engineRunning: true, playerPlaying: true, boundToSelectedDevice: true,
            pendingBuffers: 4, pendingSamples: 960,
            counters: VirtualAudioPlaybackCounters(scheduledSamples: 22_560, playedSamples: 21_600))
        return value
    }

    @Test func coldStartWaitsForTailAndPassesWithoutReplacingHistoricalSnapshot() {
        var value = attempt()
        #expect(value.outputAtStart.selectedDeviceKind == .unavailable)
        #expect(value.result == .playbackPending)
        #expect(terminal(value, final: false) != .audioDeliveryFailed)
        value.outputAtObservation.pendingBuffers = 0
        value.outputAtObservation.pendingSamples = 0
        value.outputAtObservation.counters.playedSamples = 22_560
        #expect(value.result == .deliveredToSelectedDevice)
        #expect(terminal(value, final: false) == .passed)
        #expect(value.outputAtStart.selectedDeviceKind == .unavailable)
    }

    @Test(arguments: [false, true])
    func transientReadinessAndBindingWaitUntilDeadline(binding: Bool) {
        var value = attempt()
        if binding { value.outputAtObservation.boundToSelectedDevice = false }
        else { value.outputAtObservation.engineRunning = false }
        #expect(!value.result.isConfirmedFailure)
        #expect(terminal(value, final: false) != .audioDeliveryFailed)
        #expect(terminal(value, final: true) == .audioDeliveryFailed)
    }

    @Test func lostOrInterruptedAudioRemainsFailureAfterRecovery() {
        var value = attempt()
        value.enqueueFailures = 1
        #expect(terminal(value, final: false) == .audioDeliveryFailed)
        value.enqueueFailures = 0
        value.outputAtObservation.counters.interruptedSamples = 240
        #expect(terminal(value, final: false) == .audioDeliveryFailed)
    }

    @Test func incompleteAndPendingPlaybackCannotPassAtDeadline() {
        var value = attempt()
        #expect(terminal(value, final: true) == .audioDeliveryFailed)
        value.outputAtObservation.pendingSamples = 0
        #expect(value.result == .playbackIncomplete)
        #expect(terminal(value, final: true) == .audioDeliveryFailed)
    }

    private func terminal(_ value: VoiceAudioDeliveryDiagnostic, final: Bool) -> FirstUseVoiceAttemptResult {
        FirstUseVoiceAttemptPolicy.terminalResultAfterSession(manualInputObserved: false,
            samplesReceived: true, transcriptionAppeared: true, triggerReady: true,
            focusReadyAtDeadline: true, audioDeliveryResult: value.result, finalObservation: final)
    }
}

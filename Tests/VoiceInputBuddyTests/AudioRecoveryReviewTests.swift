import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Audio recovery review regressions")
@MainActor
struct AudioRecoveryReviewTests {
    @Test(arguments: ["hardware_change", "engine_configuration_change"])
    func healthySelectedOutputKeepsActiveAndQueuedSpeech(reason: String) throws {
        let name = UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: values))
        model.started = true
        defer { model.started = false }
        model.voiceSession.isActive = true
        model.audio.output.registerPendingVoiceBuffer()
        let device = AudioDeviceInfo(id: 101, uid: model.settings.selectedAudioDeviceUID, name: "Test Mic")
        let healthy = VirtualAudioOutputDiagnosticSnapshot(engineRunning: true,
            playerPlaying: true, boundToSelectedDevice: true, pendingBuffers: 1, pendingSamples: 32_000)
        var reconfigurations = 0
        model.completeAudioRecoveryDeviceRefresh(generation: 0, reason: reason, details: "properties=devices",
            devices: [device], outputSnapshot: healthy, configureOutput: { _ in reconfigurations += 1 })
        #expect(reconfigurations == 0)
        #expect(model.audio.output.pendingVoiceBufferCountForDiagnostics == 1)
        #expect(model.voiceSession.isActive)
        // Cached health is not sufficient after the selected device disappears.
        model.completeAudioRecoveryDeviceRefresh(generation: 0, reason: reason, details: "properties=devices",
            devices: [], outputSnapshot: healthy, configureOutput: { _ in reconfigurations += 1 })
        #expect(reconfigurations == 1)
        model.completeAudioRecoveryDeviceRefresh(generation: 99, reason: reason, details: "",
            devices: [], configureOutput: { _ in reconfigurations += 1 })
        #expect(reconfigurations == 1)
    }

    @Test func unhealthyActiveEngineStillRecoversAndBoundIdleEngineDoesNotLoop() {
        #expect(AudioEngineConfigurationChangePolicy.needsRecovery(boundToSelectedDevice: true,
            configurationHealthy: false, hasActiveAudioSource: true, pendingVoiceBufferCount: 1))
        #expect(!AudioEngineConfigurationChangePolicy.needsRecovery(boundToSelectedDevice: true,
            configurationHealthy: false, hasActiveAudioSource: false, pendingVoiceBufferCount: 0))
        #expect(AudioEngineConfigurationChangePolicy.needsRecovery(boundToSelectedDevice: false,
            configurationHealthy: false, hasActiveAudioSource: false, pendingVoiceBufferCount: 0))
    }
}

import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("System sleep audio teardown")
@MainActor
struct SystemSleepAudioTests {
    @Test func actualSleepEndsActiveVoiceEvenDuringStartup() async throws {
        let name = "system-sleep-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: values), initialAudioDevices: [])
        model.started = true
        defer { model.started = false }
        model.audioStartupPending = true
        model.bluetoothVoiceActive = true
        model.isStreaming = true
        model.isAudioOutputReady = true
        model.audioOutput.registerPendingVoiceBuffer()
        model.handleSystemAudioLifecycle(.systemWillSleep)
        #expect(!model.bluetoothVoiceActive)
        #expect(!model.isStreaming)
        #expect(!model.isAudioOutputReady)
        model.audioStartupGeneration = 42
        var configurations = 0
        model.prepareAudioStartup(generation: 42, devices: [], configureOutput: { _, _ in configurations += 1 })
        #expect(configurations == 0)
        #expect(!model.audioStartupPending)
        // Wait for the real output queue without allocating an audio device.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { model.audioOutput.stop(); continuation.resume() }
        }
        #expect(model.audioOutput.pendingVoiceBufferCountForDiagnostics == 0)
    }

    @Test func screenSleepPreservesActiveVoice() throws {
        let name = "screen-sleep-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: values), initialAudioDevices: [])
        model.started = true
        defer { model.started = false }
        model.bluetoothVoiceActive = true
        model.isStreaming = true
        model.handleSystemAudioLifecycle(.screenDidSleep)
        #expect(model.bluetoothVoiceActive)
        #expect(model.isStreaming)
    }
}

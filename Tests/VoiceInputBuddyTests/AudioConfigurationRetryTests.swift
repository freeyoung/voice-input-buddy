import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Integrated microphone readiness")
@MainActor
struct AudioConfigurationRetryTests {
    private func model() throws -> BridgeAppModel {
        let values = try #require(UserDefaults(suiteName: UUID().uuidString))
        return BridgeAppModel(settings: AppSettings(defaults: values))
    }

    private func mainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test(arguments: [false, true])
    func transientFailureRetriesOnceAndReportsFinalOutcome(recovered: Bool) async throws {
        let model = try model()
        model.started = true
        model.audio.startupPending = true
        defer { model.started = false }
        var attempts = 0
        var pending: [() -> Void] = []
        var answers: [Bool] = []
        model.configureAudioOutputWithRetry(deviceUID: model.settings.selectedAudioDeviceUID,
            generation: 0, configure: { _, done in
                attempts += 1
                done(attempts == 2 && recovered)
            }, scheduleRetry: { delay, action in
                #expect(delay == 0.25)
                pending.append(action)
            }, completion: { answers.append($0) })
        await mainQueueTurn()
        #expect(answers.isEmpty)
        #expect(pending.count == 1)
        pending.removeFirst()()
        await mainQueueTurn()
        #expect(attempts == 2)
        #expect(answers == [recovered])
        #expect(pending.isEmpty)
    }

    @Test(arguments: ["new_configuration", "stop", "sleep", "idle", "quit"])
    func supersededRetryCannotReopenAudio(reason: String) async throws {
        let model = try model()
        model.started = true
        model.voiceSession.isActive = true
        defer { model.started = false }
        var pending: [() -> Void] = []
        var attempts = 0
        var answers: [Bool] = []
        model.configureAudioOutputWithRetry(deviceUID: model.settings.selectedAudioDeviceUID,
            generation: 0, configure: { _, done in attempts += 1; done(false) },
            scheduleRetry: { _, action in pending.append(action) },
            completion: { answers.append($0) })
        await mainQueueTurn()
        switch reason {
        case "new_configuration": model.audio.configurationGeneration += 1
        case "stop": model.started = false
        case "sleep": _ = model.audio.suspensionState.apply(.systemWillSleep)
        case "idle": model.voiceSession.isActive = false
        default: model.prepareForTermination()
        }
        try #require(pending.count == 1)
        pending.removeFirst()()
        #expect(attempts == 1)
        #expect(answers == [false])
    }

}

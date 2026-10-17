import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Resumable onboarding") @MainActor
struct OnboardingPauseTests {
    @Test(arguments: [OnboardingStep.audio, .permissions, .voiceTest])
    func pausePreservesStepAcrossRelaunchWithoutCompletingValidation(step: OnboardingStep) throws {
        let name = "pause-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.setOnboardingStep(step)
        let model = BridgeAppModel(settings: settings)
        var closes = 0
        let view = OnboardingView(model: model, onPauseSetup: { closes += 1 })
        model.isStreaming = true
        view.pauseIncompleteSetup()
        #expect(closes == 0)
        model.isStreaming = false
        view.pauseIncompleteSetup()
        #expect(closes == 1)
        let restored = AppSettings(defaults: defaults)
        #expect(restored.onboardingStep == step)
        #expect(!restored.isOnboardingComplete)
        #expect(restored.verifiedVoiceToolBinding == nil)
    }
}

import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Onboarding sessions")
@MainActor
struct OnboardingSessionTests {
    private func settings() throws -> AppSettings {
        let defaults = try #require(UserDefaults(suiteName: "onboarding-session-" + UUID().uuidString))
        return AppSettings(defaults: defaults)
    }

    @Test func unfinishedFirstSetupCannotBeDismissed() throws {
        let settings = try settings()
        SettingsPageBehavior.beginDeviceSetup(settings: settings)
        #expect(!settings.canDismissOnboarding)
        #expect(settings.onboardingPurpose == .initialSetup)
        settings.dismissOnboarding()
        #expect(!settings.isOnboardingComplete)
        #expect(settings.onboardingStep == .remoteAvailability)
    }

    @Test func cancellingAdditionalDeviceRestoresCompletedSetupAfterRelaunch() throws {
        let suite = "onboarding-dismiss-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let profile = settings.registerBluetoothRemote(identifier: UUID(), model: .rc003)
        settings.selectRemoteProfile(profile)
        settings.setOnboardingControlSource(.xiaomiRemote)
        settings.setOnboardingVoiceTool(.voicecursor)
        settings.voiceKeyMode = .leftCommand
        settings.voiceFnTapModeEnabled = false
        settings.verifiedVoiceToolBinding = VoiceToolUserBinding(tool: .voicecursor, shortcut: .leftCommand,
            gestureMode: .hold, source: .manuallyConfirmed, validationState: .verified)
        let originalBinding = settings.verifiedVoiceToolBinding
        settings.completeOnboarding()
        let originalProfiles = settings.remoteDeviceProfiles
        SettingsPageBehavior.beginDeviceSetup(settings: settings)
        #expect(settings.canDismissOnboarding)
        settings.setOnboardingControlSource(.chromecastRemote)
        settings.setOnboardingVoiceTool(.weixin)
        let plan = try #require(OnboardingVoicePairingPlan.resolve(
            tool: .weixin, controlSource: .chromecastRemote
        ))
        settings.beginOnboardingVoiceTrial(plan)
        settings.verifyOnboardingVoiceBinding()
        let reloaded = AppSettings(defaults: defaults)
        #expect(reloaded.canDismissOnboarding)
        #expect(reloaded.onboardingPurpose == .addDevice)
        reloaded.dismissOnboarding()
        #expect(reloaded.isOnboardingComplete)
        #expect(!reloaded.canDismissOnboarding)
        #expect(reloaded.onboardingStep == .complete)
        #expect(reloaded.onboardingControlSource == .xiaomiRemote)
        #expect(reloaded.onboardingVoiceTool == .voicecursor)
        #expect(reloaded.verifiedVoiceToolBinding == originalBinding)
        #expect(reloaded.voiceKeyMode == .leftCommand)
        #expect(!reloaded.voiceFnTapModeEnabled)
        #expect(reloaded.selectedRemoteProfileID == profile)
        #expect(reloaded.remoteDeviceProfiles == originalProfiles)
        #expect(AppSettings(defaults: defaults).isOnboardingComplete)
    }

    @Test func restartingIntegrationCanReturnToCompletedSetup() throws {
        let settings = try settings()
        settings.setOnboardingVoiceTool(.voicecursor)
        settings.completeOnboarding()
        SettingsPageBehavior.beginIntegrationSetup(tool: .weixin, settings: settings)
        #expect(settings.canDismissOnboarding)
        settings.dismissOnboarding()
        #expect(settings.isOnboardingComplete)
        #expect(settings.onboardingVoiceTool == .voicecursor)
    }

    @Test func completingIntegrationKeepsNewConfiguration() throws {
        let settings = try settings()
        settings.setOnboardingVoiceTool(.voicecursor)
        settings.completeOnboarding()
        SettingsPageBehavior.beginIntegrationSetup(tool: .weixin, settings: settings)
        settings.completeOnboarding()
        settings.dismissOnboarding()
        #expect(settings.isOnboardingComplete)
        #expect(!settings.canDismissOnboarding)
        #expect(settings.onboardingVoiceTool == .weixin)
    }

    @Test func shortenedFlowsNavigateOnlyThroughTheirOwnSteps() {
        let device = OnboardingPurpose.addDevice
        #expect(device.steps == [.remoteAvailability, .remote, .controls, .audio, .complete])
        #expect(device.previousStep(before: .remoteAvailability) == nil)
        #expect(device.nextStep(after: .audio) == .complete)
        #expect(device.previousStep(before: .complete) == .audio)
        #expect(device.progress(at: .remoteAvailability) == 0)
        #expect(device.progress(at: .controls) == 0.5)
        #expect(device.progress(at: .complete) == 1)
        let integration = OnboardingPurpose.integration
        #expect(integration.steps == [.voiceTool, .voiceTest, .complete])
        #expect(integration.previousStep(before: .voiceTool) == nil)
        #expect(integration.nextStep(after: .voiceTool) == .voiceTest)
        #expect(integration.previousStep(before: .complete) == .voiceTest)
        #expect(integration.nextStep(after: .complete) == nil)
        #expect(integration.progress(at: .voiceTest) == 0.5)
        #expect(OnboardingPurpose.initialSetup.steps == OnboardingStep.visibleCases)
    }

    @Test func repairingLostPrerequisiteExpandsFlowWithoutLosingExit() throws {
        let settings = try settings()
        settings.completeOnboarding()
        SettingsPageBehavior.beginDeviceSetup(settings: settings)
        settings.setOnboardingStep(.permissions)
        #expect(settings.onboardingPurpose == .initialSetup)
        #expect(settings.onboardingStep == .permissions)
        #expect(settings.canDismissOnboarding)
        settings.dismissOnboarding()
        #expect(settings.isOnboardingComplete)
    }

    @Test func dismissingRestoresSelectedDeviceGainAndMappings() throws {
        let settings = try settings()
        let original = settings.registerBluetoothRemote(identifier: UUID(), model: .rc003)
        settings.selectRemoteProfile(original)
        settings.gainDB = 6
        let originalBindings = settings.buttonBindings
        settings.completeOnboarding()
        SettingsPageBehavior.beginDeviceSetup(settings: settings)
        let added = settings.registerBluetoothRemote(identifier: UUID(), model: .rc003)
        settings.selectRemoteProfile(added)
        settings.gainDB = 15
        settings.dismissOnboarding()
        #expect(settings.selectedRemoteProfileID == original)
        #expect(settings.gainDB == 6)
        #expect(settings.buttonBindings == originalBindings)
        #expect(settings.remoteDeviceProfiles.contains { $0.id == added })
        #expect(settings.gainDB(for: added) == 15)
    }
}

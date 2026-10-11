import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Product privacy boundaries")
struct ProductBoundaryTests {
    @Test @MainActor func usageEventsNeverPersistCounters() throws {
        let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let buttonCount = settings.totalButtonPressCount
        let duration = settings.totalVoiceDuration
        settings.recordButtonPress()
        settings.recordVoiceDuration(12.5)
        #expect(settings.totalButtonPressCount == buttonCount)
        #expect(settings.totalVoiceDuration == duration)
        #expect(defaults.object(forKey: "usage.totalButtonPressCount") == nil)
        #expect(defaults.object(forKey: "usage.totalVoiceDuration") == nil)
    }

    @Test func unavailableFeaturesStayOutOfNavigation() {
        let sections = SettingsPageBehavior.sidebarSections(
            privateFeatureVisible: false,
            macroFeatureVisible: true,
            buttonProfilesVisible: true,
            membershipVisible: false
        )
        #expect(sections.contains(.mapping))
        #expect(sections.contains(.connection))
        #expect(!sections.contains(.statistics))
        #expect(!sections.contains(.transcripts))
        #expect(!sections.contains(.membership))
    }

    @Test func wizardRequiresEachPermissionAndKeepsRemoteControl() {
        #expect(OnboardingBuildCapabilities.availableControlSources == [.xiaomiRemote])
        let ready = OnboardingCapabilities(
            bluetoothGranted: true,
            inputMonitoringGranted: true,
            accessibilityGranted: true
        )
        #expect(OnboardingFlowPolicy.canContinue(
            from: .permissions, voiceTool: .unselected, capabilities: ready
        ))
        for keyPath in [
            \OnboardingCapabilities.bluetoothGranted,
            \OnboardingCapabilities.inputMonitoringGranted,
            \OnboardingCapabilities.accessibilityGranted
        ] {
            var missing = ready
            missing[keyPath: keyPath] = false
            #expect(!OnboardingFlowPolicy.canContinue(
                from: .permissions, voiceTool: .unselected, capabilities: missing
            ))
        }
    }

    @Test func independentMicrophoneIsAcceptedByWizard() {
        #expect(OnboardingAudioSelectionPolicy.isSupportedDevice(
            uid: DoubaoAudioDevicePolicy.deviceUID,
            name: DoubaoAudioDevicePolicy.deviceName
        ))
        #expect(!OnboardingAudioSelectionPolicy.isSupportedDevice(
            uid: "speaker", name: "MacBook Speakers"
        ))
    }

    @Test func diagnosticsCannotSendEvenWithAConfiguredLegacyService() {
        var sends = 0
        let uploader = DiagnosticLogUploader(
            configurationStateProvider: { .configured },
            sender: { _ in sends += 1 }
        )
        #expect(uploader.uploadSynchronously() == .failure(.serviceNotConfigured))
        #expect(sends == 0)
    }
}

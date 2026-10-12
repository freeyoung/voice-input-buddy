import Foundation
import AppKit
import Testing
@testable import VoiceInputBuddy

@Suite("Product privacy boundaries")
struct ProductBoundaryTests {
    @Test func releaseTagsCanBeComparedAndPreviewFallsBack() async {
        #expect(UpdateVersion.normalized("v26-10-11.021") == "26.10.11.021")
        #expect(UpdateVersion.isNewer("v26-10-11.022", than: "v26-10-11.021"))
        let stable = URL(string: "https://voice.zfdang.com/appcast-arm64.xml")!
        let preview = URL(string: "https://voice.zfdang.com/preview/appcast-arm64.xml")!
        let resolution = await UpdateFeedResolver.resolvePreviewFeed(stableURL: stable, previewURL: preview) { url in
            if url == preview { throw URLError(.fileDoesNotExist) }
            return Data("<sparkle:shortVersionString>v26-10-11.021</sparkle:shortVersionString>".utf8)
        }
        #expect(resolution.selected?.url == stable)
        #expect(resolution.selected?.version == "26.10.11.021")
    }

    @Test func updateFeedOnlyUsesProductHTTPSOrigin() {
        let selection = UpdateFeedSelection(stableFeedURLString: "https://voice.zfdang.com/appcast-arm64.xml")
        #expect(selection.feedURLString(checksForPreReleaseUpdates: false) == "https://voice.zfdang.com/appcast-arm64.xml")
        #expect(selection.feedURLString(checksForPreReleaseUpdates: true) == "https://voice.zfdang.com/preview/appcast-arm64.xml")
        for url in ["http://voice.zfdang.com/appcast-arm64.xml", "https://evil.example/appcast-arm64.xml",
                    "https://voice.zfdang.com/appcast-arm64.xml?redirect=evil", "https://user@voice.zfdang.com/appcast-arm64.xml",
                    "https://voice.zfdang.com:8443/appcast-arm64.xml", "https://voice.zfdang.com/other.xml"] {
            #expect(UpdateFeedSelection(stableFeedURLString: url).validatedStableFeedURL == nil)
        }
    }

    /// Architectural boundary: default routes may be observed, but the app must
    /// never write Core Audio's global system object to change those routes.
    @Test func systemAudioDefaultsRemainReadOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil
        ))
        let globalAudioWrite = try NSRegularExpression(
            pattern: #"AudioObjectSetPropertyData\s*\(\s*(?:AudioObjectID\s*\(\s*)?kAudioObjectSystemObject"#
        )
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(globalAudioWrite.firstMatch(in: source,
                range: NSRange(source.startIndex..., in: source)) == nil,
                "Global audio route mutation found in \(file.lastPathComponent)")
        }
    }

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

    @Test @MainActor func everySetupScreenshotAndRemoteIllustrationDecodes() throws {
        let bundle = VoiceInputBuddyResourceBundle.mainOrDevelopment
        for name in ["doubao-menu", "doubao-settings", "system-fn", "vokie-step-1",
                     "vokie-step-2", "weixin-app-shortcuts", "weixin-input-menu",
                     "weixin-input-settings"] {
            for theme in ["light", "dark"] {
                let url = try #require(bundle.url(forResource: "\(name)-\(theme)",
                    withExtension: "png", subdirectory: "Onboarding"))
                let image = try #require(NSImage(contentsOf: url))
                #expect(image.isValid)
            }
        }
        let remote = try #require(bundle.url(forResource: "BuddyRemoteIllustration",
                                            withExtension: "png"))
        #expect(try #require(NSImage(contentsOf: remote)).isValid)
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
        #expect(!SettingsSection.allCases.map(\.rawValue).contains("transcripts"))
        #expect(!sections.contains(.membership))
    }

    @Test func dailyNavigationKeepsPermissionRepairBeforeSettings() {
        let sections = SettingsPageBehavior.sidebarSections(
            privateFeatureVisible: false, macroFeatureVisible: false,
            buttonProfilesVisible: false, membershipVisible: false
        )
        #expect(sections == [.connection, .mapping, .integration, .permissions, .about])
        #expect(SettingsPageBehavior.visibleSection(for: .permissions) == .permissions)
        #expect(SettingsPageBehavior.initialSection(
            requestedSection: nil, privateFeatureVisible: false,
            macroFeatureVisible: false, buttonProfilesVisible: false,
            membershipVisible: false
        ) == .connection)
        #expect(SettingsPageBehavior.initialSection(
            requestedSection: .permissions, privateFeatureVisible: false,
            macroFeatureVisible: false, buttonProfilesVisible: false,
            membershipVisible: false
        ) == .permissions)
    }

    @Test @MainActor func changingIntegrationKeepsHardwareAudioAndMappings() throws {
        let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.selectedAudioDeviceUID = "BuddyMic2ch_UID"
        settings.gainDB = 6
        settings.customMappingEnabled = true
        settings.completeOnboarding()
        SettingsPageBehavior.beginIntegrationSetup(tool: .voicecursor, settings: settings)
        #expect(settings.selectedAudioDeviceUID == "BuddyMic2ch_UID")
        #expect(settings.gainDB == 6)
        #expect(settings.customMappingEnabled)
        #expect(settings.onboardingVoiceTool == .voicecursor)
        #expect(settings.onboardingControlSource == .xiaomiRemote)
        #expect(settings.onboardingStep == .voiceTool)
        #expect(!settings.isOnboardingComplete)
        let restored = AppSettings(defaults: defaults)
        #expect(restored.onboardingVoiceTool == .voicecursor)
        let tools = OnboardingVoiceToolVisibilityPolicy.visibleTools(availability: [:])
        #expect(tools.contains(.voicecursor))
        #expect(tools.contains(.other))
    }

    @Test @MainActor func firstRunLanguageFollowsSystemAndExplicitChoicePersists() throws {
        let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.applicationLanguage == .system)
        let localization = LocalizationStore(settings: settings)
        localization.select(.english)
        #expect(AppSettings(defaults: defaults).applicationLanguage == .english)
        localization.select(.simplifiedChinese)
        #expect(AppSettings(defaults: defaults).applicationLanguage == .simplifiedChinese)
    }

    @Test func wizardRequiresEachPermissionAndKeepsRemoteControl() {
        #expect(OnboardingBuildCapabilities.availableControlSources == [.xiaomiRemote])
        let ready = OnboardingCapabilities(
            bluetoothGranted: true,
            inputMonitoringGranted: true,
            accessibilityGranted: true
        )
        #expect(OnboardingFlowPolicy.canContinue(
            from: .permissions, voiceTool: .unselected, remoteAvailability: .unselected,
            controlMethod: .unselected, capabilities: ready
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

    @Test func driverIsRequiredAtAudioSetupRatherThanPermissions() {
        var ready = OnboardingCapabilities(
            bluetoothGranted: true, inputMonitoringGranted: true,
            accessibilityGranted: true, audioReady: true, audioOutputSelected: true
        )
        #expect(OnboardingFlowPolicy.canContinue(
            from: .permissions, voiceTool: .unselected, remoteAvailability: .unselected,
            controlMethod: .unselected, capabilities: ready
        ))
        #expect(!OnboardingFlowPolicy.canContinue(
            from: .audio, voiceTool: .unselected, capabilities: ready
        ))
        ready.microphoneDriverInstalled = true
        #expect(OnboardingFlowPolicy.canContinue(
            from: .audio, voiceTool: .unselected, capabilities: ready
        ))
    }

    @Test @MainActor func wizardStartsWithEnvironmentAndMigratesLegacyWelcome() throws {
        let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.onboardingStep == .permissions)
        #expect(settings.onboardingControlMethod == .unselected)
        #expect(OnboardingStep.permissions.previous == nil)
        #expect(OnboardingStep.permissions.next == .remoteAvailability)
        #expect(OnboardingStep.remoteAvailability.next == .remote)
        #expect(OnboardingStep.audio.next == .controls)
        #expect(OnboardingStep.controls.next == .voiceTool)
        defaults.set("welcome", forKey: "onboarding.step")
        #expect(AppSettings(defaults: defaults).onboardingStep == .permissions)
        settings.completeOnboarding()
        settings.restartOnboarding()
        #expect(settings.onboardingStep == .permissions)
        #expect(settings.onboardingControlMethod == .unselected)
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

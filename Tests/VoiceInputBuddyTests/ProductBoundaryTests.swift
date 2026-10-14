import Foundation
import AppKit
import Testing
@testable import VoiceInputBuddy

@Suite("Product privacy boundaries")
struct ProductBoundaryTests {
    @Test @MainActor func onboardingLoadsReplacementJPEGsAndRetainsDarkPNGSelection() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        let bundle = try #require(Bundle(path: resources.path))
        let paired = ["doubao-menu", "doubao-settings", "weixin-input-menu", "weixin-input-settings"]
        let microphone = ["doubao-input-microphone", "weixin-input-microphone", "voicecursor-setting-fn", "voicecursor-setting-mic"]
        for name in paired + microphone {
            let url = try #require(VoiceInputBuddyResourceBundle.onboardingImageURL(named: name, isDark: false, in: bundle))
            #expect(url.lastPathComponent == "\(name)-light.jpg")
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.size.width > 0 && image.size.height > 0)
            let dark = try #require(VoiceInputBuddyResourceBundle.onboardingImageURL(named: name, isDark: true, in: bundle))
            #expect(dark.lastPathComponent == "\(name)-\(paired.contains(name) ? "dark.png" : "light.jpg")")
        }
    }

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

    @Test @MainActor func configurationOperationsPersistPreferencesWithoutUsageData() throws {
        let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        settings.setAction(.commandCopy, for: .right)
        settings.gainDB = 12
        try settings.importConfiguration(from: settings.exportedConfigurationData())
        _ = settings.recordLaunchAndDetectCompletedUpdate(currentBuild: "80", sparkleHadLaunchedBefore: false)
        let persisted = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(!persisted.isEmpty)
        #expect(persisted.keys.allSatisfy { !$0.hasPrefix("usage.") })
        let exported = try #require(JSONSerialization.jsonObject(with: settings.exportedConfigurationData()) as? [String: Any])
        #expect(exported.keys.allSatisfy { !$0.hasPrefix("usage.") })
    }

    @Test @MainActor func everySetupScreenshotAndRemoteIllustrationDecodes() throws {
        let bundle = VoiceInputBuddyResourceBundle.mainOrDevelopment
        for name in ["doubao-menu", "doubao-settings", "system-fn", "vokie-step-1",
                     "vokie-step-2", "weixin-app-shortcuts", "weixin-input-menu",
                     "weixin-input-settings"] {
            for theme in ["light", "dark"] {
                let url = try #require(VoiceInputBuddyResourceBundle.onboardingImageURL(
                    named: name, isDark: theme == "dark", in: bundle))
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
        settings.gainDB = 6
        settings.customMappingEnabled = true
        settings.setOnboardingControlSource(.chromecastRemote)
        settings.completeOnboarding()
        SettingsPageBehavior.beginIntegrationSetup(tool: .voicecursor, settings: settings)
        #expect(settings.selectedAudioDeviceUID == "BuddyMic2ch_UID")
        #expect(settings.gainDB == 6)
        #expect(settings.customMappingEnabled)
        #expect(settings.onboardingVoiceTool == .voicecursor)
        #expect(settings.onboardingControlSource == .chromecastRemote)
        #expect(settings.onboardingPurpose == .integration)
        #expect(settings.onboardingStep == .voiceTool)
        #expect(!settings.isOnboardingComplete)
        let restored = AppSettings(defaults: defaults)
        #expect(restored.onboardingVoiceTool == .voicecursor)
        let tools = OnboardingVoiceToolVisibilityPolicy.tools
        #expect(tools.contains(.voicecursor))
        #expect(tools.contains(.other))
    }

    @Test func integrationCatalogIncludesUninstalledToolsInConsistentOrder() {
        #expect(OnboardingVoiceToolVisibilityPolicy.tools == [
            .doubao, .weixin, .typeless, .vokie, .voicecursor, .other,
        ])
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

    @Test @MainActor func plannedRemoteIllustrationsLoadWithoutUsingTheXiaomiImage() throws {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        let bundle = try #require(Bundle(path: resources.path))
        let planned = PlannedRemoteDevice.allCases.filter { $0 != .xiaomi }
        #expect(Set(planned.map(\.illustrationResource)).count == 3)
        for device in planned {
            #expect(device.illustrationResource != PlannedRemoteDevice.xiaomi.illustrationResource)
            let url = try #require(bundle.url(forResource: device.illustrationResource, withExtension: "png"))
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.size.width > 0 && image.size.height > image.size.width)
        }
    }

    @Test func deviceScopeKeepsGoogleModelsDistinctAndPlannedAdaptersUnavailable() {
        #expect(PlannedRemoteDevice.allCases == [
            .xiaomi, .chromecastG9N9N, .googleStreamerGY3LE, .siriRemote,
        ])
        #expect(PlannedRemoteDevice.chromecastG9N9N.googleHardwareModelNumber == "G9N9N")
        #expect(PlannedRemoteDevice.googleStreamerGY3LE.googleHardwareModelNumber == "GY3LE")
        #expect(PlannedRemoteDevice.allCases.filter(\.isAvailable) == [.xiaomi, .chromecastG9N9N])
        // Listing a planned device must not admit it through the Xiaomi hardware bridge.
        #expect(VoiceRemoteCatalog.entry(matchingDISModelNumber: "G9N9N") == nil)
        #expect(VoiceRemoteCatalog.entry(matchingDISModelNumber: "GY3LE") == nil)
    }

    @Test @MainActor func g9n9nSelectionPersistsWithoutClaimingAConnection() throws {
        let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let model = BridgeAppModel(settings: settings, initialAudioDevices: [])
        let view = OnboardingView(model: model)
        view.selectControlSource(.chromecastRemote)
        #expect(settings.onboardingControlSource == .chromecastRemote)
        #expect(settings.onboardingControlMethod == .physicalRemote)
        #expect(AppSettings(defaults: defaults).onboardingControlSource == .chromecastRemote)
        #expect(!model.isOnboardingControlSourceConnected(.chromecastRemote))
        #expect(OnboardingRemotePhotoKind.resolve(source: .chromecastRemote, selectedModel: .rc003)
            == .bundled(resourceName: "ChromecastG9N9NIllustration"))
        #expect(PlannedRemoteDevice.chromecastG9N9N.isAvailable)
    }

    @Test @MainActor func deviceChoicePersistsAndContinueBlocksOnlyUpcomingAdapters() throws {
        for device in PlannedRemoteDevice.allCases {
            let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = AppSettings(defaults: defaults)
            settings.setOnboardingStep(.remoteAvailability)
            let model = BridgeAppModel(settings: settings, initialAudioDevices: [])
            let view = OnboardingView(model: model)
            view.selectDevice(device)
            #expect(settings.onboardingDevice == device)
            #expect(view.canContinue)
            #expect(AppSettings(defaults: defaults).onboardingDevice == device)
            view.continueFlow()
            if device == .xiaomi || device == .chromecastG9N9N {
                #expect(settings.onboardingStep == .remote)
            } else {
                #expect(settings.onboardingStep == .remoteAvailability)
                #expect(settings.onboardingControlSource == .unselected)
                #expect(!settings.firstUseEvents.contains { $0.step == .remoteAvailability && $0.kind == .passed })
            }
            settings.restartOnboarding()
            #expect(settings.onboardingDevice == nil)
            settings.setOnboardingStep(.remoteAvailability)
            #expect(!view.canContinue)
        }
    }

    @Test func wizardRequiresEachPermissionAndKeepsRemoteControl() {
        #expect(OnboardingBuildCapabilities.availableControlSources == [.xiaomiRemote, .chromecastRemote])
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

    @Test func inputToolRequiresViewedStepsButNoMicrophoneCheckbox() {
        let passed = OnboardingCapabilities(
            voiceSessionStarted: true, voiceSamplesReceived: true,
            voiceSessionEnded: true, transcriptionAppeared: true
        )
        #expect(!OnboardingFlowPolicy.canContinue(
            from: .voiceTool, voiceTool: .unselected, capabilities: passed
        ))
        for tool in [OnboardingVoiceTool.doubao, .weixin, .vokie, .voicecursor, .typeless, .other] {
            #expect(!OnboardingFlowPolicy.canContinue(
                from: .voiceTool, voiceTool: tool, capabilities: OnboardingCapabilities()
            ))
            #expect(OnboardingFlowPolicy.canContinue(
                from: .voiceTool, voiceTool: tool,
                voiceToolGuideStepsCompleted: true, capabilities: OnboardingCapabilities()
            ))
        }
        // Step 7 verifies the input result and has no configuration confirmations.
        #expect(OnboardingFlowPolicy.canContinue(
            from: .voiceTest, voiceTool: .weixin, capabilities: passed
        ))
        var incomplete = passed
        incomplete.voiceSamplesReceived = false
        #expect(!OnboardingFlowPolicy.canContinue(
            from: .voiceTest, voiceTool: .weixin,
            capabilities: incomplete
        ))
        var typed = passed
        typed.manualTranscriptInputObserved = true
        #expect(!OnboardingFlowPolicy.canContinue(
            from: .voiceTest, voiceTool: .weixin,
            capabilities: typed
        ))
    }

    @Test @MainActor func wizardStartsWithEnvironmentAndUsesOnlyCurrentSteps() throws {
        let suite = "voice-input-buddy.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.onboardingStep == .permissions)
        #expect(settings.onboardingControlMethod == .unselected)
        settings.setOnboardingControlSource(.xiaomiRemote)
        #expect(AppSettings(defaults: defaults).onboardingControlMethod == .physicalRemote)
        #expect(OnboardingStep.permissions.previous == nil)
        #expect(OnboardingStep.permissions.next == .remoteAvailability)
        #expect(OnboardingStep.remoteAvailability.next == .remote)
        #expect(OnboardingStep.remote.next == .controls)
        #expect(OnboardingStep.controls.next == .audio)
        #expect(OnboardingStep.audio.next == .voiceTool)
        #expect(OnboardingStep(rawValue: "welcome") == nil)
        #expect(OnboardingStep(rawValue: "controlMethod") == nil)
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


}

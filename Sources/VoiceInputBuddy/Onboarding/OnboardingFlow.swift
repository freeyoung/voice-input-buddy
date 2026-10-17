import Foundation

enum OnboardingStep: String, CaseIterable, Codable {
    case voiceTool
    case remoteAvailability
    case permissions
    case remote
    case audio
    case voiceTest
    case controls
    case complete

    /// Match the main navigation: environment, connection, buttons, then integration.
    static let visibleCases: [Self] = [
        .permissions, .remoteAvailability, .remote, .controls, .audio, .voiceTool,
        .voiceTest, .complete,
    ]

    var requiresRuntime: Bool {
        switch self {
        case .remoteAvailability:
            return false
        case .permissions, .remote, .audio, .voiceTool, .voiceTest, .controls, .complete:
            return true
        }
    }

    var previous: OnboardingStep? {
        let step = self
        guard let index = Self.visibleCases.firstIndex(of: step), index > 0 else { return nil }
        return Self.visibleCases[index - 1]
    }

    var next: OnboardingStep? {
        let step = self
        guard let index = Self.visibleCases.firstIndex(of: step), index + 1 < Self.visibleCases.count else {
            return nil
        }
        return Self.visibleCases[index + 1]
    }

    var progress: Double {
        let step = self
        guard let index = Self.visibleCases.firstIndex(of: step), Self.visibleCases.count > 1 else {
            return 0
        }
        return Double(index) / Double(Self.visibleCases.count - 1)
    }
}

enum OnboardingPurpose: String, Codable {
    case initialSetup
    case addDevice
    case integration

    var steps: [OnboardingStep] {
        switch self {
        case .initialSetup: return OnboardingStep.visibleCases
        case .addDevice: return [.remoteAvailability, .remote, .controls, .complete]
        case .integration: return [.voiceTool, .voiceTest, .complete]
        }
    }

    func previousStep(before step: OnboardingStep) -> OnboardingStep? {
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    func nextStep(after step: OnboardingStep) -> OnboardingStep? {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    func progress(at step: OnboardingStep) -> Double {
        guard let index = steps.firstIndex(of: step), steps.count > 1 else { return 0 }
        return Double(index) / Double(steps.count - 1)
    }
}

enum OnboardingPhase: String, CaseIterable {
    case prepare
    case setup
    case tryIt = "try_it"

    var localizationKey: String {
        "onboarding.phase.\(rawValue)"
    }

    static func phase(for step: OnboardingStep) -> OnboardingPhase {
        switch step {
        case .remoteAvailability:
            return .prepare
        case .permissions, .remote, .audio, .voiceTool:
            return .setup
        case .voiceTest, .controls, .complete:
            return .tryIt
        }
    }
}

enum OnboardingRemoteAvailability: String, CaseIterable, Codable, Identifiable {
    case unselected
    case hasRemote = "has_remote"
    case noRemote = "no_remote"

    var id: String { rawValue }

    var titleKey: String {
        "onboarding.remote_availability.\(rawValue).title"
    }

    var detailKey: String {
        "onboarding.remote_availability.\(rawValue).detail"
    }
}

enum OnboardingControlMethod: String, CaseIterable, Codable, Identifiable {
    case unselected
    case physicalRemote = "physical_remote"

    var id: String { rawValue }

    var titleKey: String {
        "onboarding.control_method.\(rawValue).title"
    }

    var detailKey: String {
        "onboarding.control_method.\(rawValue).detail"
    }

    var requiresBluetoothPermission: Bool {
        self != .unselected
    }

    var requiresInputMonitoringPermission: Bool {
        self != .unselected
    }

}

enum OnboardingVoiceTool: String, CaseIterable, Codable, Identifiable {
    case unselected
    case weixin
    case doubao
    case bageshuo
    case typeless
    case voicecursor
    case other

    var id: String { rawValue }

    var titleKey: String {
        "onboarding.voice_tool.\(rawValue).title"
    }

    var detailKey: String {
        "onboarding.voice_tool.\(rawValue).detail"
    }

    var preferredInputSourceID: String? {
        switch self {
        case .doubao:
            return "com.bytedance.inputmethod.doubaoime.pinyin"
        case .weixin:
            return "com.tencent.inputmethod.wetype.pinyin"
        case .unselected, .bageshuo, .typeless, .voicecursor, .other:
            return nil
        }
    }

    var applicationBundleIdentifier: String? {
        switch self {
        case .bageshuo:
            return "com.bageshuo"
        case .typeless:
            return "now.typeless.desktop"
        case .unselected, .doubao, .weixin, .voicecursor, .other:
            return nil
        }
    }

    var requiresFunctionKeySetup: Bool {
        preferredInputSourceID != nil
    }
}

enum OnboardingAIAssistantPrompt {
    static let chinese = """
    请帮助我在这台 Mac 上配置「语音搭子」。遥控器已通过蓝牙连接。

    本应用目前没有自动配置命令行接口。请通过应用的设置和向导，以及公开的 macOS 无障碍界面完成配置，不要调用不存在的配置命令。

    1. 运行 open -b com.zfdang.VoiceInputBuddy 打开应用，检查向导和权限状态。
    2. 选择已连接的遥控器；有多个无法区分的设备时，请让我选择。
    3. 选择已安装的语音输入工具，按照向导配置 Fn 和适合该工具的按住或点按方式。
    4. 使用语音搭子的虚拟麦克风，保留已有增益；只有必要时再调整。
    5. 仅修改语音搭子自己的配置。不要读取或修改第三方应用的私有文件、数据库、沙盒或未公开协议。
    6. 保留真实按键、音频和语音文字上屏验证。需要权限、用户选择或真实说话时，请明确告诉我还缺什么。
    7. 根据界面可观察的结果报告配置状态，不要将配置写入当成测试通过，不要伪造完成状态。
    """

    static let english = """
    Help me configure Voice Input Buddy on this Mac. My remote is connected over Bluetooth.

    The app currently has no automatic configuration CLI. Use its settings and onboarding wizard through public macOS accessibility interfaces; do not invoke nonexistent configuration commands.

    1. Run open -b com.zfdang.VoiceInputBuddy to open the app and check onboarding and permissions.
    2. Select the connected remote; ask me to choose if multiple devices cannot be distinguished.
    3. Select an installed voice typing tool and follow the wizard to configure Fn and its matching hold or tap behavior.
    4. Use the Voice Input Buddy virtual microphone and preserve the current gain unless adjustment is needed.
    5. Modify only this app's configuration. Do not access third-party private files, databases, sandboxes or undocumented protocols.
    6. Keep real button, audio and spoken-text verification. Explain any permission, choice or real spoken test still required.
    7. Report observable results. Written configuration is not proof that voice input works. Never fabricate completion.
    """

    static func text(for locale: Locale) -> String {
        locale.identifier.lowercased().hasPrefix("zh") ? chinese : english
    }
}

enum OnboardingVoiceGesturePrompt {
    static func text(
        for mode: VoiceGestureMode,
        fnTapModeEnabled: Bool = false,
        locale: Locale
    ) -> String {
        let isChinese = locale.identifier.lowercased().hasPrefix("zh")
        if fnTapModeEnabled {
            return isChinese
                ? "按住语音键说话，说完松开（已自动开启点按转换）。"
                : "Hold the voice button while speaking, then release it (Fn tap conversion enabled)."
        }
        switch (isChinese, mode) {
        case (true, .hold): return "按住语音键说话，说完松开。"
        case (true, .toggle): return "按一下语音键开始说话，再按一下结束。"
        case (false, .hold): return "Hold the voice button while speaking, then release it."
        case (false, .toggle): return "Press the voice button once to start, then once more to finish."
        }
    }
}

enum VoiceGestureMode: String, CaseIterable, Codable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }
}

enum VoiceToolBindingSource: String, Codable {
    case documentedDefault = "documented_default"
    case userLearned = "user_learned"
    case manuallyConfirmed = "manually_confirmed"
}

enum VoiceToolBindingValidationState: String, Codable {
    case staged
    case verified
    case failed
}

enum VoiceToolEvidenceState: String, Codable {
    case verified
    case pending
    case stale
    case unknown
}

enum VoiceToolInstallationProbe: String, Codable {
    case inputSource
    case applicationBundle
    case none
}

struct VoiceToolAdapterProfile: Equatable {
    let tool: OnboardingVoiceTool
    let supportedModes: Set<VoiceGestureMode>
    let defaultShortcutByMode: [VoiceGestureMode: VoiceKeyMode]
    let recommendedMode: VoiceGestureMode?
    let installationProbe: VoiceToolInstallationProbe
    let evidenceState: VoiceToolEvidenceState

    static func profile(for tool: OnboardingVoiceTool) -> Self {
        switch tool {
        case .weixin:
            return Self(
                tool: tool,
                supportedModes: [.hold, .toggle],
                defaultShortcutByMode: [.hold: .function, .toggle: .rightCommand],
                recommendedMode: .hold,
                installationProbe: .inputSource,
                evidenceState: .pending
            )
        case .doubao:
            return Self(
                tool: tool,
                supportedModes: [.hold, .toggle],
                defaultShortcutByMode: [.hold: .function, .toggle: .rightCommand],
                recommendedMode: .hold,
                installationProbe: .inputSource,
                evidenceState: .verified
            )
        case .bageshuo:
            return Self(
                tool: tool,
                supportedModes: [.toggle],
                defaultShortcutByMode: [.toggle: .function],
                recommendedMode: .toggle,
                installationProbe: .applicationBundle,
                evidenceState: .verified
            )
        case .typeless:
            return Self(
                tool: tool,
                supportedModes: [.toggle],
                defaultShortcutByMode: [.toggle: .function],
                recommendedMode: .toggle,
                installationProbe: .applicationBundle,
                evidenceState: .verified
            )
        case .voicecursor, .other:
            return Self(
                tool: tool,
                supportedModes: [.hold, .toggle],
                // The third-party tool remains unobserved; Fn is only the
                // temporary Onboarding trigger and still requires the user's
                // real voice-text confirmation before it can be committed.
                defaultShortcutByMode: [.hold: .function, .toggle: .function],
                recommendedMode: .hold,
                installationProbe: .none,
                evidenceState: .unknown
            )
        case .unselected:
            return Self(
                tool: tool,
                supportedModes: [],
                defaultShortcutByMode: [:],
                recommendedMode: nil,
                installationProbe: .none,
                evidenceState: .unknown
            )
        }
    }
}

struct VoiceToolUserBinding: Codable, Equatable {
    let tool: OnboardingVoiceTool
    let shortcut: VoiceKeyMode
    let gestureMode: VoiceGestureMode
    let source: VoiceToolBindingSource
    var validationState: VoiceToolBindingValidationState
    var verifiedToolVersion: String?
    var verifiedAt: Date?

    func verified(at date: Date = Date()) -> Self {
        var copy = self
        copy.validationState = .verified
        copy.verifiedAt = date
        return copy
    }
}

enum OnboardingVoiceBindingPreference: String, Codable {
    case documentedDefault = "documented_default"
    case learnCurrent = "learn_current"
}

enum OnboardingControlSource: String, CaseIterable, Codable, Identifiable {
    case unselected
    case xiaomiRemote = "xiaomi_remote"
    case siriRemote = "siri_remote"
    case chromecastRemote = "chromecast_remote"

    var id: String { rawValue }

    var titleKey: String { "onboarding.control_source.\(rawValue).title" }
    var detailKey: String { "onboarding.control_source.\(rawValue).detail" }

    var supportedGestureModes: Set<VoiceGestureMode> {
        switch self {
        case .unselected:
            return []
        case .xiaomiRemote, .siriRemote, .chromecastRemote:
            return [.hold]
        }
    }

    var controlMethod: OnboardingControlMethod {
        switch self {
        case .xiaomiRemote, .siriRemote, .chromecastRemote:
            return .physicalRemote
        case .unselected:
            return .unselected
        }
    }

    static func defaultSource(for method: OnboardingControlMethod) -> Self {
        switch method {
        case .physicalRemote: return .xiaomiRemote
        case .unselected: return .unselected
        }
    }
}

/// During the ordinary-button check, Onboarding observes fresh input events but must
/// never execute mappings that the user configured before starting (or rerunning) the flow.
enum OnboardingControlValidationPolicy {
    static func suppressConfiguredActions(
        at step: OnboardingStep,
        source: OnboardingControlSource
    ) -> Bool {
        guard step == .remote || step == .controls else { return false }
        switch source {
        case .xiaomiRemote, .siriRemote, .chromecastRemote:
            return true
        case .unselected:
            return false
        }
    }
}

enum OnboardingSecureInputPolicy {
    static let warningDelay: TimeInterval = 3

    static func shouldMonitor(
        step: OnboardingStep,
        source: OnboardingControlSource
    ) -> Bool {
        guard step == .remote || step == .controls else { return false }
        switch source {
        case .xiaomiRemote, .siriRemote, .chromecastRemote:
            return true
        case .unselected:
            return false
        }
    }

    static func shouldShowWarning(
        step: OnboardingStep,
        source: OnboardingControlSource,
        remoteConnected: Bool,
        remoteButtonObserved: Bool,
        secureInputActive: Bool?,
        waitStartedAtUptime: TimeInterval?,
        nowUptime: TimeInterval
    ) -> Bool {
        guard shouldMonitor(step: step, source: source),
              remoteConnected,
              !remoteButtonObserved,
              secureInputActive == true,
              let waitStartedAtUptime
        else { return false }
        return nowUptime - waitStartedAtUptime >= warningDelay
    }
}

enum OnboardingAppleRemoteGeneration: String, Codable, CaseIterable, Identifiable {
    case generation6 = "generation_6"
    case generation7 = "generation_7"

    var id: String { rawValue }

    var titleKey: String { "onboarding.control_source.apple_remote.\(rawValue).title" }

    var model: XiaomiRemoteModel {
        switch self {
        case .generation6: return .appleSiriRemoteA2540
        case .generation7: return .appleSiriRemoteA2854
        }
    }
}

enum OnboardingBuildCapabilities {
    static var availableControlSources: [OnboardingControlSource] {
        let sources = PlannedRemoteDevice.allCases.compactMap(\.onboardingSource)
        return sources.reduce(into: []) { unique, source in
            if !unique.contains(source) { unique.append(source) }
        }
    }
}

struct OnboardingVoicePairingPlan: Equatable {
    let binding: VoiceToolUserBinding
    let controlSource: OnboardingControlSource
    let fnTapModeEnabled: Bool
    let chromecastVoiceMode: ChromecastVoiceMode?
    let evidenceState: VoiceToolEvidenceState

    static func resolve(
        tool: OnboardingVoiceTool,
        controlSource: OnboardingControlSource,
        preferredGesture: VoiceGestureMode? = nil,
        userBinding: VoiceToolUserBinding? = nil,
        forceFunctionKey: Bool = false
    ) -> Self? {
        guard tool != .unselected, controlSource != .unselected else { return nil }
        let profile = VoiceToolAdapterProfile.profile(for: tool)

        if let userBinding {
            var effectiveBinding = userBinding
            if forceFunctionKey {
                effectiveBinding = VoiceToolUserBinding(
                    tool: userBinding.tool,
                    shortcut: .function,
                    gestureMode: userBinding.gestureMode,
                    source: userBinding.source,
                    validationState: userBinding.validationState,
                    verifiedToolVersion: userBinding.verifiedToolVersion,
                    verifiedAt: userBinding.verifiedAt
                )
            }
            guard effectiveBinding.tool == tool,
                  profile.supportedModes.contains(effectiveBinding.gestureMode),
                  canDrive(
                    gesture: effectiveBinding.gestureMode,
                    shortcut: effectiveBinding.shortcut,
                    from: controlSource
                  ) else { return nil }
            return makePlan(
                binding: effectiveBinding,
                controlSource: controlSource,
                evidenceState: profile.evidenceState
            )
        }

        let candidates = gestureCandidates(
            profile: profile,
            controlSource: controlSource,
            preferredGesture: preferredGesture
        )
        for gesture in candidates {
            let shortcut = forceFunctionKey ? VoiceKeyMode.function : profile.defaultShortcutByMode[gesture]
            guard let shortcut,
                  canDrive(gesture: gesture, shortcut: shortcut, from: controlSource)
            else { continue }
            return makePlan(
                binding: VoiceToolUserBinding(
                    tool: tool,
                    shortcut: shortcut,
                    gestureMode: gesture,
                    source: .documentedDefault,
                    validationState: .staged,
                    verifiedToolVersion: nil,
                    verifiedAt: nil
                ),
                controlSource: controlSource,
                evidenceState: profile.evidenceState
            )
        }
        return nil
    }

    private static func gestureCandidates(
        profile: VoiceToolAdapterProfile,
        controlSource: OnboardingControlSource,
        preferredGesture: VoiceGestureMode?
    ) -> [VoiceGestureMode] {
        var result: [VoiceGestureMode] = []
        func append(_ mode: VoiceGestureMode?) {
            guard let mode, profile.supportedModes.contains(mode), !result.contains(mode) else {
                return
            }
            result.append(mode)
        }
        append(preferredGesture)
        if controlSource.supportedGestureModes.contains(.hold) { append(.hold) }
        append(profile.recommendedMode)
        append(.toggle)
        append(.hold)
        return result
    }

    private static func canDrive(
        gesture: VoiceGestureMode,
        shortcut: VoiceKeyMode,
        from source: OnboardingControlSource
    ) -> Bool {
        if source.supportedGestureModes.contains(gesture) { return true }
        return gesture == .toggle &&
            shortcut == .function &&
            source.supportedGestureModes == [.hold]
    }

    private static func makePlan(
        binding: VoiceToolUserBinding,
        controlSource: OnboardingControlSource,
        evidenceState: VoiceToolEvidenceState
    ) -> Self {
        let fnTap = binding.gestureMode == .toggle &&
            binding.shortcut == .function &&
            !controlSource.supportedGestureModes.contains(.toggle)
        let chromecastMode: ChromecastVoiceMode? = controlSource == .chromecastRemote
            ? (binding.gestureMode == .toggle ? .toggle : .hold)
            : nil
        return Self(
            binding: binding,
            controlSource: controlSource,
            fnTapModeEnabled: fnTap,
            chromecastVoiceMode: chromecastMode,
            evidenceState: evidenceState
        )
    }
}

/// Onboarding 右栏使用的遥控器图片来源。
///
/// 物理遥控器的图片必须跟随用户选择的来源，不能把一张小米图片当成所有硬件的占位图。
enum OnboardingRemotePhotoKind: Equatable {
    case bundled(resourceName: String)
    case siriRemote
    case chromecastRemote
    case placeholder

    static func resolve(
        source: OnboardingControlSource,
        selectedModel: XiaomiRemoteModel?,
        selectedDevice: PlannedRemoteDevice? = nil
    ) -> Self {
        switch source {
        case .xiaomiRemote:
            // Only a Xiaomi profile may refine the image. A previously selected
            // Apple/Chromecast profile must never replace the Xiaomi card artwork.
            if let selectedModel,
               selectedModel == .rc001 || selectedModel == .rc003 {
                guard let resource = VoiceRemoteCatalog.photoResource(for: selectedModel) else {
                    return .placeholder
                }
                return .bundled(resourceName: resource)
            }
            return .bundled(resourceName: VoiceRemoteCatalog.photoResource(for: .rc003)
                ?? "RC003-remote-photo")
        case .siriRemote:
            return .siriRemote
        case .chromecastRemote:
            if let selectedDevice, selectedDevice.onboardingSource == .chromecastRemote {
                return .bundled(resourceName: selectedDevice.illustrationResource)
            }
            return .bundled(resourceName: PlannedRemoteDevice.chromecastG9N9N.illustrationResource)
        case .unselected:
            return .placeholder
        }
    }
}

enum OnboardingVoiceToolAvailability: String, Equatable, Hashable {
    case available
    case notInstalled
    case unknown
}

enum OnboardingVoiceToolVisibilityPolicy {
    // Discovery affects availability badges and setup readiness, not the catalog.
    // Both onboarding and Settings must expose the same supported integrations.
    static let tools = OnboardingVoiceTool.allCases.filter { $0 != .unselected }
}

enum OnboardingVoiceToolRuntimeState: String, Equatable, Hashable {
    case running
    case notRunning = "not_running"
    case unknown
    case notApplicable = "not_applicable"
}

enum OnboardingVoiceToolRuntimePolicy {
    static func requiresRunningApplication(for tool: OnboardingVoiceTool) -> Bool {
        switch VoiceToolAdapterProfile.profile(for: tool).installationProbe {
        case .applicationBundle:
            return true
        case .inputSource, .none:
            return false
        }
    }

}

struct OnboardingCapabilities: Equatable {
    var systemFunctionKeyAvailable = false
    var bluetoothGranted = false
    var inputMonitoringGranted = false
    var accessibilityGranted = false
    var remoteConnected = false
    var remoteButtonObserved = false
    var microphoneDriverInstalled = false
    var audioReady = false
    var audioOutputSelected = false
    var voiceSessionStarted = false
    var voiceSamplesReceived = false
    var voiceSessionEnded = false
    var transcriptionAppeared = false
    var manualTranscriptInputObserved = false
    var testedRemoteButtonCount = 0
}

enum OnboardingAudioSelectionPolicy {
    private static let supportedUIDs = [DoubaoAudioDevicePolicy.deviceUID]

    static func isSupportedDevice(uid: String, name: String) -> Bool {
        supportedUIDs.contains(uid)
    }

    static func isSupportedDeviceSelected(
        selectedUID: String,
        availableSupportedUIDs: some Sequence<String>
    ) -> Bool {
        selectedUID == DoubaoAudioDevicePolicy.deviceUID && availableSupportedUIDs.contains(selectedUID)
    }
}

enum OnboardingTranscriptInputPolicy {
    static func canEditText(keyCode: UInt16, characters: String?, commandHeld: Bool) -> Bool {
        // Navigation, shortcuts and function keys are not evidence of manual text.
        guard !commandHeld else { return false }
        if [51, 117].contains(keyCode) { return true }
        return characters?.unicodeScalars.contains { !CharacterSet.controlCharacters.contains($0) &&
            !(0xF700...0xF8FF).contains($0.value) } == true
    }

    static func isManualPaste(eventTypeRawValue: UInt?, sourceStateID: Int64?,
        sourceUnixProcessID: Int64?) -> Bool {
        // Context-menu paste has no keyDown; a physical Cmd-V is manual. Synthetic
        // key events from dictation tools must remain eligible for voice validation.
        guard eventTypeRawValue == keyDownEventTypeRawValue else { return true }
        return isConfirmedPhysicalKeyboardInput(eventTypeRawValue: eventTypeRawValue,
            sourceStateID: sourceStateID, sourceUnixProcessID: sourceUnixProcessID)
    }

    private static let keyDownEventTypeRawValue: UInt = 10
    private static let hidSystemStateRawValue: Int64 = 1

    static func isConfirmedPhysicalKeyboardInput(
        eventTypeRawValue: UInt?,
        sourceStateID: Int64?,
        sourceUnixProcessID: Int64?
    ) -> Bool {
        guard eventTypeRawValue == keyDownEventTypeRawValue,
              sourceStateID == hidSystemStateRawValue,
              let sourceUnixProcessID,
              sourceUnixProcessID <= 0 else {
            return false
        }
        return true
    }
}

enum OnboardingVoiceTestConfigurationPolicy {
    static func requiresGlobalVoiceConfirmation(for voiceTool: OnboardingVoiceTool) -> Bool {
        voiceTool == .doubao
    }
}

enum OnboardingFlowPolicy {
    static func isPhysicalRemoteRecognized(
        at step: OnboardingStep,
        voiceConnectionReady: Bool,
        validatedHIDButtonObserved: Bool
    ) -> Bool {
        voiceConnectionReady || (step == .remote && validatedHIDButtonObserved)
    }

    static func shouldAutoSelectPhysicalRemote(
        at step: OnboardingStep,
        remoteConnected: Bool,
        suppressForUserBack: Bool = false
    ) -> Bool {
        step == .remoteAvailability && remoteConnected && !suppressForUserBack
    }

    static func shouldRequestRemoteReconnect(
        remoteConnected: Bool,
        remoteButtonObserved: Bool,
        recoveryRequested: Bool
    ) -> Bool {
        !remoteConnected && remoteButtonObserved && !recoveryRequested
    }

    static func shouldAdvanceDriverCheck(step: OnboardingStep, driverInstalled: Bool, outputReady: Bool) -> Bool {
        step == .audio && driverInstalled && outputReady
    }

    static func canContinue(
        from step: OnboardingStep,
        voiceTool: OnboardingVoiceTool,
        remoteAvailability: OnboardingRemoteAvailability = .hasRemote,
        controlMethod: OnboardingControlMethod = .physicalRemote,
        voiceKeyMode: VoiceKeyMode = .function,
        voiceToolGuideStepsCompleted: Bool = false,
        selectedDevice: PlannedRemoteDevice? = nil,
        capabilities: OnboardingCapabilities
    ) -> Bool {
        if [.remote, .controls, .audio, .voiceTest].contains(step),
           missingRuntimePermission(controlMethod: controlMethod, capabilities: capabilities) != nil {
            return false
        }
        switch step {
        case .voiceTool:
            return voiceTool != .unselected && voiceToolGuideStepsCompleted
        case .remoteAvailability:
            return selectedDevice?.canStartSetup == true
        case .permissions:
            // Environment setup must work before a control device is selected.
            return capabilities.bluetoothGranted &&
                capabilities.inputMonitoringGranted &&
                capabilities.accessibilityGranted
        case .remote:
            return capabilities.remoteConnected && capabilities.remoteButtonObserved
        case .audio:
            return capabilities.microphoneDriverInstalled &&
                capabilities.audioOutputSelected &&
                capabilities.audioReady
        case .voiceTest:
            return capabilities.voiceSessionStarted &&
                capabilities.voiceSamplesReceived &&
                capabilities.voiceSessionEnded &&
                capabilities.transcriptionAppeared &&
                !capabilities.manualTranscriptInputObserved
        case .controls:
            return capabilities.testedRemoteButtonCount >= 3
        case .complete:
            return isControlSelectionValid(
                remoteAvailability: remoteAvailability,
                controlMethod: controlMethod
            ) &&
                (!controlMethod.requiresBluetoothPermission || capabilities.bluetoothGranted) &&
                (!controlMethod.requiresInputMonitoringPermission ||
                    capabilities.inputMonitoringGranted) &&
                capabilities.accessibilityGranted &&
                capabilities.remoteConnected &&
                capabilities.audioOutputSelected &&
                capabilities.audioReady
        }
    }

    static func missingRuntimePermission(controlMethod: OnboardingControlMethod,
                                         capabilities: OnboardingCapabilities) -> FirstUseFailureReason? {
        if controlMethod.requiresBluetoothPermission && !capabilities.bluetoothGranted {
            return .bluetoothPermissionDenied
        }
        if controlMethod.requiresInputMonitoringPermission && !capabilities.inputMonitoringGranted {
            return .inputMonitoringPermissionDenied
        }
        if !capabilities.accessibilityGranted { return .accessibilityPermissionDenied }
        return nil
    }

    static func recoveryStep(
        from step: OnboardingStep,
        voiceTool: OnboardingVoiceTool,
        remoteAvailability: OnboardingRemoteAvailability = .hasRemote,
        controlMethod: OnboardingControlMethod = .physicalRemote,
        capabilities: OnboardingCapabilities,
        hasSelectedAudioUID: Bool
    ) -> OnboardingStep? {
        let context = FirstUseDiagnosticContext(
            step: step,
            remoteAvailability: remoteAvailability,
            controlMethod: controlMethod,
            capabilities: capabilities,
            hasSelectedAudioUID: hasSelectedAudioUID
        )
        guard let failure = context.failureReason else { return nil }
        if step == .complete, failure == .completeRuntimeRegressed {
            if !isControlSelectionValid(
                remoteAvailability: remoteAvailability,
                controlMethod: controlMethod
            ) {
                return .remoteAvailability
            }
            if (controlMethod.requiresBluetoothPermission && !capabilities.bluetoothGranted) ||
                (controlMethod.requiresInputMonitoringPermission &&
                    !capabilities.inputMonitoringGranted) ||
                !capabilities.accessibilityGranted {
                return .permissions
            }
            if !capabilities.remoteConnected { return .remote }
            return .audio
        }
        return failure.recoveryStep
    }

    static func isControlSelectionValid(
        remoteAvailability: OnboardingRemoteAvailability,
        controlMethod: OnboardingControlMethod
    ) -> Bool {
        switch remoteAvailability {
        case .hasRemote:
            return controlMethod == .physicalRemote
        case .noRemote:
            return false
        case .unselected:
            return false
        }
    }
}

enum OnboardingLaunchPolicy {
    static func shouldStartRuntime(isComplete: Bool, step: OnboardingStep) -> Bool {
        isComplete || step.requiresRuntime
    }

    static func shouldShowMainWindow(
        isComplete: Bool,
        completedUpdate: Bool,
        openMainWindowAtLaunch: Bool
    ) -> Bool {
        !isComplete || completedUpdate || openMainWindowAtLaunch
    }
}

enum CompletedUpdatePermissionRepairPolicy {
    static func shouldOpenPermissions(
        isOnboardingComplete: Bool,
        completedUpdate: Bool,
        bluetoothGranted: Bool,
        inputMonitoringGranted: Bool,
        accessibilityGranted: Bool
    ) -> Bool {
        isOnboardingComplete &&
            completedUpdate &&
            (!bluetoothGranted || !inputMonitoringGranted || !accessibilityGranted)
    }
}

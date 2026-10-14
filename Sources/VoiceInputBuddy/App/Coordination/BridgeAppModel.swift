import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

final class BridgeAppModel: ObservableObject, XiaomiBluetoothBridgeDelegate {
    static let longRecordingOpenTimeout: TimeInterval = 5
    static let longRecordingCloseTimeout: TimeInterval = 2
    static let rc003VoiceExtensionOpenTimeout: TimeInterval = 5
    static let rc003VoiceExtensionInterval: TimeInterval = 8
    static let rc003VoiceExtensionMaximumDuration: TimeInterval = 120

    let settings: AppSettings
    let commonPhraseStore: CommonPhraseStore
    lazy var commonPhrases = CommonPhraseController(store: commonPhraseStore)
    let loginItemService: LoginItemService

    @Published var connectionStatus = LocalizedMessage("bluetooth.status.initializing")
    @Published var hidStatus = LocalizedMessage("button_mapping.status.disabled")
    @Published var audioStatus = LocalizedMessage("audio.output.none_selected")
    @Published var doubaoAudioStatus = LocalizedMessage("audio.compatibility.checking")
    @Published var isStreaming = false
    @Published var isConnected = false
    @Published var isVoiceTriggerEnabled = false
    @Published var activeRemoteButtons = Set<RemoteButton>()
    @Published var activeAppleRemoteControlIDs = Set<String>()
    /// Chromecast 画布的活动按键（控制 ID）。与苹果遥控器链路完全隔离，互不清除。
    @Published private(set) var activeChromecastControlIDs = Set<String>()
    @Published var lastRemoteButtonPress: RemoteButton?
    @Published var connectedRemoteProfileIDs = Set<UUID>()
    @Published var remoteBatteryLevels: [UUID: Int] = [:]
    @Published var remotePowerStates: [UUID: RemotePowerState] = [:]
    var pendingRemoteBatteryLevels: [UUID: Int] = [:]
    var pendingRemotePowerStates: [UUID: RemotePowerState] = [:]
    var pendingRemoteModels: [UUID: XiaomiRemoteModel] = [:]
    @Published var remoteSystemDeviceNames: [UUID: String] = [:]
    @Published var audioDevices: [AudioDeviceInfo] = []
    @Published var testToneStatus = LocalizedMessage("audio.output.none_selected")
    @Published var isPlayingTestTone = false
    @Published var isAudioOutputReady = false
    @Published var hasReceivedCurrentVoiceSamples = false
    @Published var activeVoiceSource: RemoteInputSource?
    @Published var lastMobileRemoteButtonObservation: MobileRemoteButtonObservation?
    @Published var isPhoneRemoteConnectionEnabled = false
    @Published var isPhoneRemoteConnected = false
    @Published var isWatchRemoteConnected = false
    @Published private(set) var phoneRemoteInvitation: PhoneRemoteInvitation?
    @Published var webRemoteState: WebRemoteSessionState = .disabled
    @Published var voiceShortcutStatus = LocalizedMessage("voice_button.status.preparing")
    @Published var voiceKeyCompatibilityWarning: VoiceKeyCompatibilityWarning?
    let audioOutput = VirtualAudioOutput()

    func isOnboardingControlSourceConnected(_ source: OnboardingControlSource) -> Bool {
        switch source {
        case .xiaomiRemote:
            return connectedRemoteProfileIDs.contains { profileID in
                guard let model = settings.remoteDeviceProfiles.first(where: {
                    $0.id == profileID
                })?.model else { return false }
                return !model.usesPrivateAdapter && !model.isChromecastRemote
            }
        case .siriRemote:
            return !connectedAppleRemoteProfileIDs.isEmpty
        case .chromecastRemote:
            return connectedRemoteProfileIDs.contains { id in
                settings.remoteDeviceProfiles.first(where: { $0.id == id })?.model.isChromecastRemote == true
            }
        case .appleCompanion:
            return isPhoneRemoteConnected || isWatchRemoteConnected
        case .webRemote:
            if case .connected = webRemoteState { return true }
            return false
        case .unselected:
            return false
        }
    }

    var activePhysicalVoiceControlSource: OnboardingControlSource? {
        if bluetoothVoiceActive {
            let profile = activeBluetoothVoiceDeviceIdentifier.flatMap { settings.profileID(forBluetoothIdentifier: $0) }
                .flatMap { id in settings.remoteDeviceProfiles.first { $0.id == id } }
            return profile?.model.isChromecastRemote == true ? .chromecastRemote : .xiaomiRemote
        }
        if !appleRemoteVoiceDevices.isEmpty || appleRemoteVoiceStopping { return .siriRemote }
        return nil
    }
    let phoneRemoteServer = PhoneRemoteServer(logger: { message in
        AppLogger.shared.write(message)
    })
    let watchBluetoothServer = WatchBluetoothRemoteServer(logger: { message in
        AppLogger.shared.write(message)
    })
    let webRemoteClient = WebRemoteRelayClient()
    let voiceFunctionMapper = RemoteVoiceFunctionMapper()
    lazy var preferredInputSourceMonitor = PreferredInputSourceMonitor(
        voiceTool: { [weak self] in
            self?.settings.onboardingVoiceTool ?? .unselected
        }
    )
    lazy var voiceInputDestinationCoordinator = VoiceInputDestinationCoordinator(
        onStateChange: { [weak self] state in
            self?.handleVoiceInputDestinationState(state)
        }
    )
    lazy var voiceFnTapSession = VoiceFnTapSessionController(
        destinationReadiness: { [weak self] completion in
            self?.voiceInputDestinationCoordinator.waitUntilReady(completion: completion) ?? .immediate
        },
        setFunctionKeyPressed: { KeyboardInjector.setFunctionKeyPressed($0) },
        enqueueAudio: { [weak self] samples in
            self?.enqueueVoiceFnTapAudio(samples)
        },
        drainAudio: { [weak self] operationID, completion in
            guard let self else {
                completion()
                return
            }
            self.audioOutput.endSessionAfterDraining(
                source: "voice_fn_tap",
                operationID: operationID
            ) { outcome in
                AppLogger.shared.write(
                    "VOICE FN TAP playback_stop operation_id=\(operationID) " +
                        "phase=completed result=\(outcome.rawValue)"
                )
                completion()
            }
        },
        onFailure: { [weak self] failure in
            self?.handleVoiceFnTapFailure(failure)
        },
        logger: { AppLogger.shared.write($0) },
        onIdle: { [weak self] in self?.flushPendingVoiceToolMappingRefresh() }
    )
    private var voiceToolCancellable: AnyCancellable?
    var testToneGeneration = 0
    var voiceKeyLatch = VoiceFunctionKeyLatch()
    var heldVoiceKeyMode: VoiceKeyMode?
    var pendingVoiceKeyMode: VoiceKeyMode?
    // Main-queue state; only input-source waits can pump/reenter that queue.
    var voiceKeyActivationInProgress = false
    var pendingVoiceToolMappingRefresh = false
    var pendingCommandVoiceAudio = CommandVoiceActivationAudioBuffer()
    var voiceSessionID: UUID?
    var voiceAudioDeliveryGeneration = 0
    var voiceAudioDeliveryDiagnostic = VoiceAudioDeliveryDiagnostic()
    var bluetoothVoiceActive = false
    var loggedBluetoothVoiceAudioDeviceIdentifier: UUID?
    var mobileVoiceLifecycle = MobileVoiceLifecycleState()
    var pendingMobileVoiceStartSource: MobileVoiceSource?
    var pendingMobileVoiceAudio = CommandVoiceActivationAudioBuffer(
        maximumSampleCount: 32_000
    )
    var pendingMobileVoiceStopRequested = false
    var pendingMobileVoiceRestartCompletion: ((RemoteVoiceStartResult) -> Void)?
    var mobileVoiceNoAudioRecoveryTimer: DispatchSourceTimer?
    var activeMobileVoiceSource: MobileVoiceSource? {
        mobileVoiceLifecycle.activeSource
    }
    var stoppingMobileVoiceSource: MobileVoiceSource? {
        mobileVoiceLifecycle.stoppingSource
    }
    var mobileVoiceAudioBatchCount = 0
    var mobileVoiceAudioReceivedBatchCount = 0
    var mobileVoiceAudioEnqueueFailureCount = 0
    var mobileVoiceAudioSourceMismatchCount = 0
    var mobileVoiceAudioSignalMetrics = WatchBluetoothAudioSignalMetrics()
    var mobileVoiceOperationCounter: UInt64 = 0
    var activeMobileVoiceOperationID: String?
    var activeMobileVoiceStartedAt: Date?
    var longRecordingRequested = false
    var longRecordingGeneration: UInt64 = 0
    var longRecordingOpenTimer: DispatchSourceTimer?
    var longRecordingCloseTimer: DispatchSourceTimer?
    let rc003VoiceExtensionTestEnabled: Bool
    weak var rc003VoiceExtensionBridge: XiaomiBluetoothBridge?
    var rc003VoiceExtensionActive = false
    var rc003VoiceExtensionAwaitingReopen = false
    var rc003VoiceExtensionGeneration: UInt64 = 0
    var rc003VoiceExtensionDidReceiveAudio = false
    var rc003VoiceExtensionTimer: DispatchSourceTimer?
    var rc003VoiceExtensionOpenTimer: DispatchSourceTimer?
    var rc003VoiceExtensionDeadlineTimer: DispatchSourceTimer?
    var phoneApprovalAlert: NSAlert?
    var webApprovalAlert: NSAlert?
    var remoteButtonTitles: [String: String] = [:]
    var mobileButtonGestureRecognizers: [RemoteInputSource: RemoteButtonGestureRecognizer] = [:]
    var mobileDoubleClickTimers: [MobileButtonGestureKey: DispatchSourceTimer] = [:]
    var mobileLongPressTimers: [MobileButtonGestureKey: DispatchSourceTimer] = [:]
    var bluetoothBridges: [UUID: XiaomiBluetoothBridge] = [:]
    var bluetoothBridgeStates: [ObjectIdentifier: BluetoothBridgeState] = [:]
    var discoveryBluetoothBridge: XiaomiBluetoothBridge?
    let pendingBluetoothVoiceStart = BluetoothPendingAudioStart()
    var pendingBluetoothVoiceStopRequested = false
    var activeBluetoothVoiceDeviceIdentifier: UUID?
    var bluetoothVoiceTraceCounter: UInt64 = 0
    var activeBluetoothVoiceTraceID: UInt64?
    var bluetoothVoiceTraceStartedAt: Date?
    var bluetoothVoiceTraceModel: XiaomiRemoteModel = .unknown
    var bluetoothVoiceDecodedBatchCount = 0
    var bluetoothVoiceDecodedSampleCount = 0
    var bluetoothVoiceEnqueueFailureCount = 0
    var bluetoothVoiceTraceRoute = "none"
    var bluetoothVoiceTailDiagnostics = BluetoothVoiceTailDiagnostics()
    let hidEventSuppressor = KeyboardEventSuppressor()
    var hidMonitoringInterrupted = false
    var hidMonitors: [String: HIDRemoteMonitor] = [:]
    var discoveryHIDMonitor: HIDRemoteMonitor?
    lazy var siriRemoteFeature = SiriRemoteFeatureIntegration(
        logger: { AppLogger.shared.write($0) }
    )
    @Published private(set) var siriRemoteAudioStatus = "disabled"
    let siriRemoteCursorFeedback = SiriRemoteCursorFeedbackController(
        logger: { AppLogger.shared.write($0) }
    )
    var appleRemoteProfileIDs: [SiriRemoteDeviceIdentity: UUID] = [:]
    var connectedAppleRemoteProfileIDs = Set<UUID>()
    var appleRemoteActiveButtons: [SiriRemoteDeviceIdentity: Set<RemoteButton>] = [:]
    var appleRemoteActiveControlIDs: [SiriRemoteDeviceIdentity: Set<String>] = [:]
    var appleRemoteHoverClickDevices = Set<SiriRemoteDeviceIdentity>()
    var appleRemoteGestureRecognizers:
        [SiriRemoteDeviceIdentity: RemoteButtonGestureRecognizer] = [:]
    var appleRemoteDoubleClickTimers:
        [AppleRemoteButtonGestureKey: DispatchSourceTimer] = [:]
    var appleRemoteLongPressTimers:
        [AppleRemoteButtonGestureKey: DispatchSourceTimer] = [:]
    var appleRemoteRepeatTimers:
        [AppleRemoteButtonGestureKey: DispatchSourceTimer] = [:]
    var appleRemoteRepeatCounts: [AppleRemoteButtonGestureKey: Int] = [:]
    var appleRemoteRepeatOperationIDs: [AppleRemoteButtonGestureKey: UInt64] = [:]
    var appleRemoteRepeatOperationCounter: UInt64 = 0
    let appleRemoteAppSwitcherSession = KeyboardInjector.AppSwitcherSession()
    var appleRemoteAppSwitcherTimeout: DispatchSourceTimer?
    var appleRemoteAppSwitcherFrontmostMonitor: DispatchSourceTimer?
    var appleRemoteAppSwitcherOriginBundleIdentifier: String?
    var appleRemoteAppSwitcherOperationCounter: UInt64 = 0
    var appleRemoteAppSwitcherOperationID: UInt64?
    var appleRemoteAppSwitcherProfileID: UUID?
    var appleRemoteAppSwitcherStartedUptime: TimeInterval?
    var appleRemoteAppSwitcherTabCount = 0
    var appleRemoteAppSwitcherTouchNavigationSteps = 0
    var appleRemoteAppSwitcherButtonLeftCount = 0
    var appleRemoteAppSwitcherButtonRightCount = 0
    var appleRemoteAppSwitcherTouchConfirmationCount = 0
    var appleRemoteAppSwitcherButtonConfirmationCount = 0
    var appleRemoteCircularNavigation = AppleRemoteCircularNavigationAccumulator()
    var appleRemoteVoiceDevices = Set<SiriRemoteDeviceIdentity>()
    var appleRemoteVoiceStopping = false
    var pendingAppleRemoteVoiceStarts = Set<SiriRemoteDeviceIdentity>()
    var pendingAppleRemoteVoiceAudio = CommandVoiceActivationAudioBuffer(
        maximumSampleCount: 32_000
    )
    var pendingAppleRemoteVoiceStops = DeviceVoiceStopRequests<SiriRemoteDeviceIdentity>()
    var appleRemoteVoiceStopOperation: UInt64 = 0
    var appleRemoteVoiceCaptureRetryAttempt = 0
    var appleRemoteVoiceCaptureRetryWorkItem: DispatchWorkItem?
    var appleRemoteAudioBatchCount = 0
    var appleRemoteAudioSampleCount = 0
    var appleRemoteAudioEnqueueFailureCount = 0
    var appleRemoteAudioStopPendingBuffers = 0
    var appleRemoteAudioStopPendingSamples = 0
    var appleRemoteAudioStopInterruptedBuffers = 0
    var appleRemoteAudioStopInterruptedSamples = 0
    var loggedAppleRemoteAudioDevice = false
    var appleRemoteVoiceOperationCounter: UInt64 = 0
    var activeAppleRemoteVoiceOperationID: String?
    var activeAppleRemoteVoiceStartedAt: Date?

    /// 苹果遥控器**自报**的能力位；链路不可用时为空集合（同上）。
    @Published private(set) var siriDeclaredCapabilities: SiriRemoteDeclaredCapabilities = []

    /// 当前选中遥控器档案的语音能力：**该遥控器所在链路的自报**优先，自报缺失才回退型号默认表。
    ///
    /// 两条链路各自上报（Chromecast 走 ATVV、苹果遥控器走 HID），必须按型号取对应的那一份，
    /// 不能混用——串用会让不具备该能力的遥控器凭空多出功能入口。
    var selectedRemoteVoiceCapabilities: RemoteVoiceCapabilities {
        let model = settings.selectedRemoteProfile?.model
        var declared: ChromecastDeclaredCapabilities = []
        if let model {
            if model.isAppleSiriRemote {
                declared = siriDeclaredCapabilities.asDeclaredVoiceCapabilities
            }
        }
        return .resolve(model: model, declared: declared)
    }
    /// Google readiness derives from the shared public Bluetooth bridges.
    var connectedChromecastProfileIDs = Set<UUID>()
    var hidPowerKeySuppressed = false
    var hidAllowedLocationIDs: Set<UInt32>?
    var started = false
    var remoteDeviceNameRefreshOperation: UInt64 = 0
    var appliedHIDPermissionSnapshot: HIDPermissionSnapshot?
    private var terminationObserver: NSObjectProtocol?
    var completedUpdateHIDRecoveryWorkItem: DispatchWorkItem?
    var hidMappingRecoveryWorkItem: DispatchWorkItem?
    var hidMappingRecoveryAttempt = 0
    var hidMappingRecoveryGeneration: UInt64 = 0
    let audioPreparationQueue = DispatchQueue(label: "VoiceInputBuddy.audioPreparation", qos: .userInitiated)
    var audioConfigurationGeneration: UInt64 = 0
    var audioStartupGeneration: UInt64 = 0
    var audioDeviceRefreshGeneration: UInt64 = 0
    var audioStartupPending = false
    let audioHardwareListenerQueue = DispatchQueue(label: "VoiceInputBuddy.audioHardware")
    var observedAudioHardwareAddresses: [AudioObjectPropertyAddress] = []
    var audioRecoveryWorkItem: DispatchWorkItem?
    var audioRecoveryGeneration: UInt64 = 0
    var audioRecoveryCoalescingState = AudioRecoveryCoalescingState()
    var virtualAudioReleaseGeneration: UInt64 = 0
    var pendingVirtualAudioRelease: (generation: UInt64, reason: String)?
    var systemAudioSuspensionState = SystemAudioSuspensionState()
    lazy var audioHardwareListener: AudioObjectPropertyListenerBlock = { [weak self] count, addresses in
        let properties = Self.audioHardwarePropertyNames(count: count, addresses: addresses)
        self?.scheduleAudioRecovery(reason: "hardware_change", details: "properties=\(properties)")
    }

    var isRC003VoiceExtensionTestEnabled: Bool {
        rc003VoiceExtensionTestEnabled
    }

    init(
        settings: AppSettings = AppSettings(),
        commonPhraseStore: CommonPhraseStore = CommonPhraseStore(),
        initialAudioDevices: [AudioDeviceInfo] = [],
        loginItemService: LoginItemService = LoginItemService(),
        rc003VoiceExtensionTestEnabled: Bool =
            ProcessInfo.processInfo.arguments.contains("--rc003-voice-extension-test") ||
            (Bundle.main.object(forInfoDictionaryKey: "RC003VoiceExtensionTestEnabled") as? Bool == true)
    ) {
        self.settings = settings
        self.commonPhraseStore = commonPhraseStore

        self.loginItemService = loginItemService
        self.rc003VoiceExtensionTestEnabled = rc003VoiceExtensionTestEnabled
        if settings.siriRemoteEnabled, settings.siriRemoteNeedsUserAction {
            siriRemoteAudioStatus = "unavailable:authorization_user_action_required"
        }
        commonPhrases.onWillOpen = { [weak self] in self?.cancelPendingCommonPhraseButtonActions() }
        audioDevices = initialAudioDevices
        hidEventSuppressor.onSystemDisabled = { [weak self] in
            // Stop mapping as well: an unseized remote must not inject actions without filtering.
            guard let self else { return }
            self.hidMonitoringInterrupted = true
            self.stopHIDMonitors()
            let permissions = HIDPermissionSnapshot.current
            self.appliedHIDPermissionSnapshot = permissions
            self.hidStatus = LocalizedMessage(
                !permissions.inputMonitoringGranted ? "button_mapping.permission.input_monitoring_required" :
                    (!permissions.accessibilityGranted ? "button_mapping.permission.accessibility_required" :
                        "button_mapping.status.interrupted")
            )
        }
        appleRemoteAppSwitcherSession.setDiagnosticLogger { [weak self] message in
            AppLogger.shared.write(
                "APPLE REMOTE APP SWITCHER EVENT " +
                    "operation_id=\(self?.appleRemoteAppSwitcherOperationLabel ?? "none") " +
                    message
            )
        }
        voiceToolCancellable = settings.$onboardingVoiceTool
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.voiceToolDidChange()
            }
        audioOutput.onConfigurationChange = { [weak self] in
            self?.scheduleAudioRecovery(reason: "engine_configuration_change")
        }
        phoneRemoteServer.onConnectionStateChange = { [weak self] connected in
            DispatchQueue.main.async {
                guard let self else { return }
                if connected && !OnboardingBuildCapabilities.availableControlSources.contains(.appleCompanion) {
                    self.disablePhoneRemoteConnection()
                    return
                }
                self.isPhoneRemoteConnected = connected
            }
        }
        phoneRemoteServer.onInvitationChange = { [weak self] invitation in
            DispatchQueue.main.async {
                self?.phoneRemoteInvitation = invitation
            }
        }
        phoneRemoteServer.onApprovalCancelled = { [weak self] in
            self?.cancelPhoneApproval()
        }
        phoneRemoteServer.onApprovalRequested = { [weak self] deviceName, pairingCode, fingerprint, completion in
            guard let self, self.isPhoneRemoteConnectionEnabled,
                  OnboardingBuildCapabilities.availableControlSources.contains(.appleCompanion) else {
                completion(false)
                return
            }
            requestPhoneApproval(
                deviceName: deviceName,
                pairingCode: pairingCode,
                identityFingerprint: fingerprint,
                completion: completion
            )
        }
        phoneRemoteServer.onCommand = { [weak self] button, completion in
            DispatchQueue.main.async {
                guard let button = Self.appRemoteButton(rawValue: button.rawValue) else {
                    completion(false)
                    return
                }
                self?.observeMobileButton(button, source: .nearbyPhone)
                completion(self?.performPhoneCommand(button, source: .nearbyPhone) ?? false)
            }
        }
        phoneRemoteServer.onButtonEvent = { [weak self] button, phase, completion in
            DispatchQueue.main.async {
                guard let button = Self.appRemoteButton(rawValue: button.rawValue),
                      let phase = Self.appRemoteButtonPhase(rawValue: phase.rawValue)
                else {
                    completion(false)
                    return
                }
                if phase == .press {
                    self?.observeMobileButton(button, source: .nearbyPhone)
                }
                completion(self?.handleMobileButtonEvent(
                    button,
                    phase: phase,
                    source: .nearbyPhone
                ) ?? false)
            }
        }
        phoneRemoteServer.onButtonEventsReset = { [weak self] in
            DispatchQueue.main.async {
                self?.resetMobileButtonGestures(source: .nearbyPhone)
            }
        }
        phoneRemoteServer.onVoiceStartResult = { [weak self] completion in
            DispatchQueue.main.async {
                guard let self else {
                    completion(.unavailable)
                    return
                }
                self.requestPhoneVoiceStart(
                    source: .nearbyPhone,
                    completion: completion
                )
            }
        }
        phoneRemoteServer.onVoiceStop = { [weak self] in
            DispatchQueue.main.async {
                self?.stopPhoneVoice(source: .nearbyPhone)
            }
        }
        phoneRemoteServer.onAudio = { [weak self] samples in
            DispatchQueue.main.async {
                self?.receivePhoneAudio(samples, source: .nearbyPhone)
            }
        }
        watchBluetoothServer.onConnectionStateChange = { [weak self] connected in
            DispatchQueue.main.async {
                guard let self else { return }
                if connected && !OnboardingBuildCapabilities.availableControlSources.contains(.appleCompanion) {
                    self.disablePhoneRemoteConnection()
                    return
                }
                self.isWatchRemoteConnected = connected
            }
        }
        watchBluetoothServer.onApprovalCancelled = { [weak self] in
            self?.cancelPhoneApproval()
        }
        watchBluetoothServer.onApprovalRequested = { [weak self] deviceName, pairingCode, fingerprint, completion in
            guard let self, self.isPhoneRemoteConnectionEnabled,
                  OnboardingBuildCapabilities.availableControlSources.contains(.appleCompanion) else {
                completion(false)
                return
            }
            requestPhoneApproval(
                deviceName: deviceName,
                pairingCode: pairingCode,
                identityFingerprint: fingerprint,
                completion: completion
            )
        }
        watchBluetoothServer.onCommand = { [weak self] button, completion in
            DispatchQueue.main.async {
                guard let button = Self.appRemoteButton(rawValue: button.rawValue) else {
                    completion(false)
                    return
                }
                self?.observeMobileButton(button, source: .nearbyPhone)
                completion(self?.performPhoneCommand(button, source: .nearbyPhone, phraseSource: "watch") ?? false)
            }
        }
        watchBluetoothServer.onButtonEvent = { [weak self] button, phase, completion in
            DispatchQueue.main.async {
                guard let button = Self.appRemoteButton(rawValue: button.rawValue),
                      let phase = Self.appRemoteButtonPhase(rawValue: phase.rawValue)
                else {
                    completion(false)
                    return
                }
                if phase == .press {
                    self?.observeMobileButton(button, source: .nearbyPhone)
                }
                completion(self?.handleMobileButtonEvent(
                    button,
                    phase: phase,
                    source: .nearbyPhone,
                    phraseSource: "watch"
                ) ?? false)
            }
        }
        watchBluetoothServer.onButtonEventsReset = { [weak self] in
            DispatchQueue.main.async {
                self?.resetMobileButtonGestures(source: .nearbyPhone, phraseSource: "watch")
            }
        }
        watchBluetoothServer.onVoiceStartResult = { [weak self] completion in
            DispatchQueue.main.async {
                guard let self else {
                    completion(.unavailable)
                    return
                }
                self.requestPhoneVoiceStart(
                    source: .nearbyWatch,
                    completion: completion
                )
            }
        }
        watchBluetoothServer.onVoiceStop = { [weak self] in
            DispatchQueue.main.async {
                self?.stopPhoneVoice(source: .nearbyWatch)
            }
        }
        watchBluetoothServer.onAudio = { [weak self] samples in
            DispatchQueue.main.async {
                self?.receivePhoneAudio(samples, source: .nearbyWatch)
            }
        }
        webRemoteClient.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.webRemoteState = state }
        }
        webRemoteClient.onApprovalCancelled = { [weak self] in
            self?.cancelWebApproval()
        }
        webRemoteClient.onApprovalRequested = { [weak self] deviceName, pairingCode, completion in
            guard let self else {
                completion(false)
                return
            }
            requestWebApproval(
                deviceName: deviceName,
                pairingCode: pairingCode,
                completion: completion
            )
        }
        webRemoteClient.onCommand = { [weak self] button, completion in
            DispatchQueue.main.async {
                guard let button = Self.appRemoteButton(rawValue: button.rawValue) else {
                    completion(false)
                    return
                }
                self?.observeMobileButton(button, source: .webRemote)
                completion(self?.performPhoneCommand(button, source: .webRemote) ?? false)
            }
        }
        webRemoteClient.onButtonEvent = { [weak self] button, phase, completion in
            DispatchQueue.main.async {
                guard let button = Self.appRemoteButton(rawValue: button.rawValue),
                      let phase = Self.appRemoteButtonPhase(rawValue: phase.rawValue)
                else {
                    completion(false)
                    return
                }
                if phase == .press {
                    self?.observeMobileButton(button, source: .webRemote)
                }
                completion(self?.handleMobileButtonEvent(
                    button,
                    phase: phase,
                    source: .webRemote
                ) ?? false)
            }
        }
        webRemoteClient.onButtonEventsReset = { [weak self] in
            DispatchQueue.main.async {
                self?.resetMobileButtonGestures(source: .webRemote)
            }
        }
        webRemoteClient.onVoiceStart = { [weak self] completion in
            DispatchQueue.main.async {
                guard let self else {
                    completion(false)
                    return
                }
                self.requestPhoneVoiceStart(source: .web) {
                    completion($0 == .started)
                }
            }
        }
        webRemoteClient.onVoiceStop = { [weak self] in
            DispatchQueue.main.async {
                self?.stopPhoneVoice(source: .web)
            }
        }
        webRemoteClient.onAudio = { [weak self] samples in
            DispatchQueue.main.async {
                self?.receivePhoneAudio(samples, source: .web)
            }
        }

    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        startAudioSubsystem()
        applyHIDSettings()
        refreshRemoteDeviceNames(reason: .startup)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development"
        AppLogger.shared.write(
            "APP START version=\(version) rc003_test=\(rc003VoiceExtensionTestEnabled)"
        )
    }

    func stop() {
        commonPhrases.close(reason: "app_stop")
        resetAllAppleRemoteState(reason: "app_stop")
        pendingAppleRemoteVoiceStarts.removeAll()
        pendingAppleRemoteVoiceStops.removeAll()
        appleRemoteVoiceDevices.removeAll()
        appleRemoteVoiceStopping = false
        appleRemoteVoiceStopOperation &+= 1

        preferredInputSourceMonitor.stop()
        guard started else { return }
        started = false
        cancelHIDMappingRecovery(reason: "app_stop")
        completedUpdateHIDRecoveryWorkItem?.cancel()
        completedUpdateHIDRecoveryWorkItem = nil
        audioStartupGeneration &+= 1
        audioDeviceRefreshGeneration &+= 1
        audioStartupPending = false
        audioRecoveryGeneration &+= 1
        audioRecoveryWorkItem?.cancel()
        audioRecoveryWorkItem = nil
        audioRecoveryCoalescingState.reset()
        stopObservingAudioHardware()
        cancelTestToneIfNeeded(
            statusMessage: LocalizedMessage("app.status.stopped"),
            logReason: "app_stop"
        )
        stopLongRecording(reason: "app_stop")
        finishRC003VoiceExtensionTest(reason: "app_stop")
        voiceInputDestinationCoordinator.shutdown()
        voiceFnTapSession.shutdown()
        bluetoothBridges.values.forEach { $0.stop() }
        discoveryBluetoothBridge?.stop()
        bluetoothBridges.removeAll()
        bluetoothBridgeStates.removeAll()
        discoveryBluetoothBridge = nil
        pendingBluetoothVoiceStart.cancel()
        pendingBluetoothVoiceStopRequested = false
        activeBluetoothVoiceDeviceIdentifier = nil
        phoneRemoteServer.stop()
        watchBluetoothServer.stop()
        webRemoteClient.stop()
        isPhoneRemoteConnectionEnabled = false
        isPhoneRemoteConnected = false
        isWatchRemoteConnected = false
        webRemoteState = .disabled
        bluetoothVoiceActive = false
        let cancelledPendingRestart = mobileVoiceLifecycle.reset()
        cancelMobileVoiceNoAudioRecoveryTimer()
        mobileVoiceAudioReceivedBatchCount = 0
        activeMobileVoiceOperationID = nil
        activeMobileVoiceStartedAt = nil
        let completion = pendingMobileVoiceRestartCompletion
        pendingMobileVoiceRestartCompletion = nil
        pendingMobileVoiceStartSource = nil
        pendingMobileVoiceAudio.cancel()
        pendingMobileVoiceStopRequested = false
        if cancelledPendingRestart {
            completion?(.unavailable)
        }
        releaseVoiceKeyIfNeeded()
        stopHIDMonitors()
        isAudioOutputReady = false
        virtualAudioReleaseGeneration &+= 1
        pendingVirtualAudioRelease = nil
        // Stop is serialized with configurations on the engine queue. Enumeration no
        // longer allocates audio resources, so a delayed preparation-queue stop is unsafe.
        audioOutput.stop()
        voiceFunctionMapper.restore()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        AppLogger.shared.write("APP STOP")
    }

}

import AppKit
import Combine
import CoreBluetooth
import BuddyRemoteUI
import BuddyRemoteCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: BridgeAppModel
    @ObservedObject var settings: AppSettings
    @EnvironmentObject var localization: LocalizationStore
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.colorSchemeContrast) var colorSchemeContrast
    let completeRuntimeReadyOverride: Bool?
    let allowsInputSourceSwitching: Bool
    let systemFunctionKeyAvailableOverride: Bool?
    let voiceToolAvailabilityOverride: [OnboardingVoiceTool: OnboardingVoiceToolAvailability]?
    let remoteInputDiagnosticOverride: FirstUseRemoteInputDiagnostic?
    let interactionProbe: OnboardingInteractionProbe?

    @State var bluetoothAuthorization = CBManager.authorization
    @State var inputMonitoringGranted = HIDRemoteMonitor.isInputMonitoringGranted
    @State var accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
    @State var observedRemoteButtons = Set<RemoteButton>()
    @State var remoteInputDiagnostic = FirstUseRemoteInputDiagnostic()
    @State var requestedRemoteConnectionRecovery = false
    @State var testedControlButtons = Set<RemoteButton>()
    @State var hidBindingProfile: RemoteDeviceProfile?
    @State var voiceSessionStarted = false
    @State var voiceSamplesReceived = false
    @State var voiceSessionEnded = false
    @State var transcript = ""
    @State var transcriptCommitRequest = 0
    @State var lastVoiceTranscriptCandidate = ""
    @State var manualTranscriptInputObserved = false
    @State var lastRecordedFailure: FirstUseFailureReason?
    @State var inputSourceSwitchResult: OnboardingInputSourceSwitchResult = .notApplicable
    @State var voiceToolAvailability: [OnboardingVoiceTool: OnboardingVoiceToolAvailability] = [:]
    @State var voiceToolRuntimeState: [OnboardingVoiceTool: OnboardingVoiceToolRuntimeState] = [:]
    @State var systemFunctionKeyUsage = OnboardingSystemFunctionKeyUsage.current
    @State var selectedInputMethodGuideStep: Int?
    @State var completedInputMethodGuideSteps = Set<Int>()
    @State var transcriptFocusRequest = 0
    @State var transcriptEditorMounted = false
    @State var transcriptWindowKey = false
    @State var transcriptFirstResponder = false
    @State var voiceAttempt = FirstUseVoiceAttemptDiagnostic()
    @State var voiceAttemptStartedAtUptime: TimeInterval?
    @State var voiceTranscriptWaitStartedAtUptime: TimeInterval?
    @State var activeFocusLossStartedAtUptime: TimeInterval?
    @State var voiceTranscriptDeadlineToken = UUID()
    @State var voiceTestTasks: [ScheduledOperation] = []
    @State var suppressConnectedPhysicalRemoteAutoRouteOnce = false
    @State var isCapturingVoiceShortcut = false
    @State var shortcutCaptureErrorKey: String?
    @State var vokieDeepLinkStatus: VoiceInputBuddyDeepLinkStatus?
    @State var secureInputActive: Bool?
    @State var secureInputWaitStartedAtUptime: TimeInterval?
    @State var lastLoggedSecureInputState: Bool?
    @State var aiPromptCopyResult: Bool?
    @State var showUnsupportedDeviceNotice = false

    init(
        model: BridgeAppModel,
        completeRuntimeReadyOverride: Bool? = nil,
        allowsInputSourceSwitching: Bool = true,
        systemFunctionKeyAvailableOverride: Bool? = nil,
        voiceToolAvailabilityOverride: [OnboardingVoiceTool: OnboardingVoiceToolAvailability]? = nil,
        initialInputMethodGuideStep: Int? = nil,
        remoteInputDiagnosticOverride: FirstUseRemoteInputDiagnostic? = nil,
        interactionProbe: OnboardingInteractionProbe? = nil
    ) {
        self.model = model

        settings = model.settings
        self.completeRuntimeReadyOverride = completeRuntimeReadyOverride
        self.allowsInputSourceSwitching = allowsInputSourceSwitching
        self.systemFunctionKeyAvailableOverride = systemFunctionKeyAvailableOverride
        self.voiceToolAvailabilityOverride = voiceToolAvailabilityOverride
        self.remoteInputDiagnosticOverride = remoteInputDiagnosticOverride
        self.interactionProbe = interactionProbe
        _voiceToolAvailability = State(
            initialValue: voiceToolAvailabilityOverride ?? Self.detectVoiceToolAvailability()
        )
        _selectedInputMethodGuideStep = State(initialValue: initialInputMethodGuideStep)
    }

    private var lifecycleContent: some View {
        VStack(spacing: 0) {
            phaseHeader
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    leftPane
                        .frame(width: max(520, proxy.size.width * 0.53))
                    rightPane
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .environment(\.locale, localization.locale)
        .frame(minWidth: 980, minHeight: 732)
        .sheet(item: $hidBindingProfile) { profile in
            RemoteHIDBindingPicker(model: model, profile: profile)
                .environmentObject(localization)
        }
        .onAppear {
            refreshPermissionStates()
            refreshVoiceToolAvailability()
            prepareForStep(settings.onboardingStep)
            refreshSecureInputState()
        }
        .task(id: settings.onboardingStep) { @MainActor in
            while !Task.isCancelled, settings.onboardingStep != .complete {
                let ready = bluetoothAuthorization == .allowedAlways && inputMonitoringGranted && accessibilityGranted
                do { try await Task.sleep(for: .seconds(ready ? 5 : 1)) }
                catch { return }
                guard !Task.isCancelled else { return }
                refreshPermissionStates()
                refreshSecureInputState()
                if settings.onboardingStep == .voiceTool { refreshSystemFunctionKeyUsage() }
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification))) { _ in
                guard settings.onboardingStep == .voiceTest else { return }
                refreshSelectedVoiceToolRuntimeState()
            }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStates()
            switch settings.onboardingStep {
            case .voiceTool:
                refreshVoiceToolAvailability()
                refreshSelectedInputMethodStatus()
                refreshSystemFunctionKeyUsage()
            case .voiceTest:
                requestTranscriptFocus()
            case .remoteAvailability:
                routeConnectedPhysicalRemoteIfNeeded()
            case .remote:
                prepareSelectedControlConnection()
            case .audio:
                model.refreshAudioDevices()
            case .complete:
                prepareSelectedControlConnection()
                model.refreshAudioDevices()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceInputBuddyDeepLinkReceived)) { notification in
            guard let request = notification.object as? VoiceInputBuddyDeepLinkRequest,
                  request.source == "vokie" else { return }
            vokieDeepLinkStatus = request.status
            refreshVoiceToolAvailability()
        }
        .onReceive(model.$isConnected.removeDuplicates()) { isConnected in
            guard isConnected else { return }
            routeConnectedPhysicalRemoteIfNeeded()
        }
    }

    private var remoteObservedContent: some View {
        lifecycleContent
        .onReceive(model.$activeRemoteButtons) { buttons in
            guard settings.onboardingControlMethod == .physicalRemote,
                  selectedPhysicalRemoteProfileMatchesSource,
                  !buttons.isEmpty else { return }
            if settings.onboardingStep == .remote {
                recordRemoteControlButtons(buttons, source: "physical_remote")
                recoverRemoteConnectionIfNeeded()
            } else if settings.onboardingStep == .controls {
                testedControlButtons.formUnion(buttons)
            }
        }
        .onReceive(model.$lastRemoteButtonPress.compactMap { $0 }) { button in
            guard settings.onboardingControlMethod == .physicalRemote,
                  selectedPhysicalRemoteProfileMatchesSource else { return }
            if settings.onboardingStep == .remote {
                recordRemoteControlButtons(Set([button]), source: "physical_remote")
                recoverRemoteConnectionIfNeeded()
            } else if settings.onboardingStep == .controls {
                testedControlButtons.insert(button)
            }
        }
        .onReceive(model.$lastMobileRemoteButtonObservation.compactMap { $0 }) { observation in
            guard selectedControlAccepts(observation.source) else { return }
            if settings.onboardingStep == .remote {
                recordRemoteControlButtons(Set([observation.button]), source: observation.source.rawValue)
            } else if settings.onboardingStep == .controls {
                testedControlButtons.insert(observation.button)
            }
        }
        .onReceive(model.$isStreaming) { isStreaming in
            guard selectedControlAcceptsVoice(model.activeVoiceSource) else { return }
            switch settings.onboardingStep {
            case .remote where isStreaming:
                recordRemoteVoiceButtonPress()
            case .voiceTest:
                if isStreaming {
                    beginVoiceAttempt(triggerPath: model.activeVoiceSource?.rawValue ?? "unknown")
                } else if voiceSessionStarted {
                    endVoiceAttempt()
                }
            default:
                break
            }
        }
        .onReceive(model.$hasReceivedCurrentVoiceSamples.removeDuplicates()) { hasReceivedSamples in
            guard settings.onboardingStep == .voiceTest,
                  hasReceivedSamples,
                  selectedControlAcceptsVoice(model.activeVoiceSource) else { return }
            voiceSamplesReceived = true
            voiceAttempt.audioDelivery = model.voiceAudioDeliveryDiagnosticSnapshot()
            if voiceAttempt.firstSampleLatencyMilliseconds == nil,
               let voiceAttemptStartedAtUptime {
                voiceAttempt.firstSampleLatencyMilliseconds = elapsedMilliseconds(
                    sinceUptime: voiceAttemptStartedAtUptime
                )
            }
        }
    }

    private var toolObservedContent: some View {
        remoteObservedContent
        .onDisappear { cancelVoiceTestTasks() }
        .onChange(of: settings.onboardingStep) { _, step in
            cancelVoiceTestTasks()
            prepareForStep(step)
        }
        .onChange(of: settings.onboardingVoiceTool) { _, _ in
            refreshSelectedVoiceToolRuntimeState()
        }
    }

    var body: some View {
        toolObservedContent
        .onChange(of: transcript) { _, updatedText in
            captureVoiceTranscriptCandidate(updatedText)
            guard settings.onboardingStep == .voiceTest,
                  !updatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let currentEvent = NSApp.currentEvent
            let currentCGEvent = currentEvent?.cgEvent
            guard OnboardingTranscriptInputPolicy.isConfirmedPhysicalKeyboardInput(
                eventTypeRawValue: currentEvent?.type.rawValue,
                sourceStateID: currentCGEvent?.getIntegerValueField(.eventSourceStateID),
                sourceUnixProcessID: currentCGEvent?.getIntegerValueField(
                    .eventSourceUnixProcessID
                )
            ) else { return }
            manualTranscriptInputObserved = true
            AppLogger.shared.write("ONBOARDING TRANSCRIPT manual_keyboard_input=true")
            finishVoiceAttempt(result: .manualInput)
        }
        .onChange(of: transcriptionAppeared) { _, appeared in
            guard appeared,
                  voiceSessionEnded,
                  !manualTranscriptInputObserved else { return }
            refreshVoiceAttemptObservableState(atDeadline: false)
            if voiceAttempt.audioDelivery.result == .deliveredToSelectedDevice {
                finishVoiceAttempt(result: .passed)
            } else {
                scheduleVoiceCompletionEvaluation(attemptID: voiceAttempt.attemptID)
            }
        }
        .onChange(of: failureReason) { _, failure in
            recordFailureTransition(failure)
        }
    }

}

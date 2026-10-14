import AppKit

final class PreferredInputSourceMonitor {
    typealias VoiceToolProvider = () -> OnboardingVoiceTool
    typealias InputSourcePreparer = (OnboardingVoiceTool) -> OnboardingInputSourceSwitchResult
    typealias CurrentInputSourceIDProvider = () -> String?
    typealias InputSourceRestorer = (String) -> OnboardingInputSourceSwitchResult
    typealias InputSourceActivationWaiter = (
        String,
        CurrentInputSourceIDProvider,
        () -> Bool
    ) -> Bool
    typealias MonitorInstaller = (@escaping (Bool) -> Void) -> Any?
    typealias MonitorRemover = (Any) -> Void
    typealias Logger = (String) -> Void

    private let voiceTool: VoiceToolProvider
    private let prepareInputSource: InputSourcePreparer
    private let currentInputSourceID: CurrentInputSourceIDProvider
    private let restoreInputSource: InputSourceRestorer
    private let waitForInputSourceActivation: InputSourceActivationWaiter
    private let installMonitor: MonitorInstaller
    private let removeMonitor: MonitorRemover
    private let logger: Logger

    private var monitor: Any?
    private var functionKeyIsPressed = false
    private var explicitVoiceSessionActivationPending = false
    private var explicitActivationGeneration: UInt64 = 0
    private var managedInputSourceSession: ManagedInputSourceSession?
    private static let activationTimeout: TimeInterval = 0.5
    private static let activationPollInterval: TimeInterval = 0.02

    var functionKeyIsPressedForDiagnostics: Bool {
        functionKeyIsPressed
    }

    private struct ManagedInputSourceSession {
        enum Owner: Hashable {
            case functionKey
            case explicitVoice
        }

        let previousInputSourceID: String?
        let targetInputSourceID: String
        var owners: Set<Owner>
        var activationPending: Bool
        var voiceTriggerSubmitted = false
    }

    init(
        voiceTool: @escaping VoiceToolProvider,
        prepareInputSource: @escaping InputSourcePreparer = OnboardingInputSourceSwitcher.prepareForVoiceSession,
        currentInputSourceID: @escaping CurrentInputSourceIDProvider = OnboardingInputSourceSwitcher.currentInputSourceID,
        restoreInputSource: @escaping InputSourceRestorer = OnboardingInputSourceSwitcher.selectEnabledInputSource,
        waitForInputSourceActivation: @escaping InputSourceActivationWaiter = { target, current, continuing in
            waitForActivation(target: target, current: current, shouldContinue: continuing)
        },
        installMonitor: @escaping MonitorInstaller = { handler in
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                // Ordered software voice sessions own their source lifecycle.
                // A delayed global event must not create a second Fn owner.
                guard shouldObserveFunctionEvent(marker: event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0) else { return }
                handler(event.modifierFlags.contains(.function))
            }
        },
        removeMonitor: @escaping MonitorRemover = NSEvent.removeMonitor,
        logger: @escaping Logger = AppLogger.shared.write
    ) {
        self.voiceTool = voiceTool
        self.prepareInputSource = prepareInputSource
        self.currentInputSourceID = currentInputSourceID
        self.restoreInputSource = restoreInputSource
        self.waitForInputSourceActivation = waitForInputSourceActivation
        self.installMonitor = installMonitor
        self.removeMonitor = removeMonitor
        self.logger = logger
    }

    // Main-thread only. `.common` is a registration pseudo-mode, not a runnable
    // mode. Preserve the active concrete mode (including AppKit event tracking).
    static func activationRunLoopMode(_ current: RunLoop.Mode?) -> RunLoop.Mode {
        guard let current, current != .common else { return .default }
        return current
    }

    static func waitForActivation(
        target: String, current: CurrentInputSourceIDProvider, shouldContinue: () -> Bool,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        currentMode: () -> RunLoop.Mode? = { RunLoop.main.currentMode },
        pump: (RunLoop.Mode, TimeInterval) -> Void = { mode, interval in
            _ = RunLoop.main.run(mode: mode, before: Date().addingTimeInterval(interval))
        }
    ) -> Bool {
        let selectionDeadline = now() + activationTimeout
        let settlingDuration: TimeInterval = 0.05
        var selectedSince: TimeInterval?
        while shouldContinue() {
            let time = now()
            if current() == target {
                if selectedSince == nil {
                    guard time <= selectionDeadline else { return false }
                    selectedSince = time
                }
                if let selectedSince, time - selectedSince >= settlingDuration { return true }
            } else {
                selectedSince = nil
                if time >= selectionDeadline { return false }
            }
            let remaining = selectedSince.map { $0 + settlingDuration - time } ?? (selectionDeadline - time)
            pump(activationRunLoopMode(currentMode()), min(activationPollInterval, max(0, remaining)))
        }
        return false
    }

    func start() {
        guard monitor == nil else { return }
        monitor = installMonitor { [weak self] pressed in
            self?.handleFunctionKeyPressed(pressed)
        }
    }

    func stop(preservingExplicitVoiceSession: Bool = false) {
        if !preservingExplicitVoiceSession {
            explicitVoiceSessionActivationPending = false
            explicitActivationGeneration &+= 1
        }
        finishManagedInputSourceSession(
            reason: "monitor_stop",
            owner: preservingExplicitVoiceSession ? .functionKey : nil
        )
        if let monitor {
            removeMonitor(monitor)
            self.monitor = nil
        }
        functionKeyIsPressed = false
    }

    func handleFunctionKeyPressed(_ pressed: Bool) {
        guard pressed != functionKeyIsPressed else { return }
        functionKeyIsPressed = pressed
        if !pressed {
            let selectedVoiceTool = voiceTool()
            if selectedVoiceTool.preferredInputSourceID != nil || managedInputSourceSession != nil {
                logger(
                    "VOICE INPUT function_key edge=up tool=\(selectedVoiceTool.rawValue)"
                )
            }
            finishManagedInputSourceSession(
                reason: "function_key_up",
                owner: .functionKey
            )
            return
        }

        let selectedVoiceTool = voiceTool()
        if selectedVoiceTool.preferredInputSourceID != nil || managedInputSourceSession != nil {
            logger(
                "VOICE INPUT function_key edge=down tool=\(selectedVoiceTool.rawValue)"
            )
        }
        if beginVoiceSession(reason: "function_key_down", owner: .functionKey) {
            // A physical Fn edge has already reached the input system.
            markVoiceTriggerSubmitted()
        }
    }

    static func shouldObserveFunctionEvent(marker: Int64) -> Bool {
        marker != KeyboardInjector.orderedVoiceEventMarker
    }

    /// Starts the input-source session for a software-emitted voice key.
    /// Command keys do not produce the Fn `flagsChanged` event that the legacy
    /// monitor observes, so their lifecycle is driven explicitly by the voice
    /// session instead of by every ordinary Command press on the Mac keyboard.
    @discardableResult
    func beginVoiceSession() -> Bool {
        explicitActivationGeneration &+= 1
        let generation = explicitActivationGeneration
        explicitVoiceSessionActivationPending = true
        defer {
            if explicitActivationGeneration == generation { explicitVoiceSessionActivationPending = false }
        }
        return beginVoiceSession(
            reason: "voice_session_start",
            owner: .explicitVoice,
            activationShouldContinue: { [weak self] in
                self?.explicitVoiceSessionActivationPending == true && self?.explicitActivationGeneration == generation
            }
        )
    }

    /// Record successful key submission separately from source activation.
    /// A failed/cancelled start can still roll back its input-source selection.
    func markVoiceTriggerSubmitted() {
        managedInputSourceSession?.voiceTriggerSubmitted = true
    }

    /// Release source ownership, retaining the selected input method after an
    /// actual trigger. Key-up ends recording, not asynchronous text composition.
    func endVoiceSession() {
        explicitVoiceSessionActivationPending = false
        explicitActivationGeneration &+= 1
        finishManagedInputSourceSession(
            reason: "voice_session_end",
            owner: .explicitVoice
        )
    }

    @discardableResult
    private func beginVoiceSession(
        reason: String,
        owner: ManagedInputSourceSession.Owner,
        activationShouldContinue: () -> Bool = { true }
    ) -> Bool {
        let selectedVoiceTool = voiceTool()
        if selectedVoiceTool.preferredInputSourceID != nil || managedInputSourceSession != nil {
            logger(
                "VOICE INPUT session edge=down reason=\(reason) " +
                    "tool=\(selectedVoiceTool.rawValue)"
            )
        }
        guard let targetInputSourceID = selectedVoiceTool.preferredInputSourceID else { return true }
        if var session = managedInputSourceSession {
            guard session.targetInputSourceID == targetInputSourceID else {
                logger("VOICE INPUT session_rejected reason=target_changed")
                return false
            }
            if session.activationPending {
                let currentSourceID = currentInputSourceID()
                guard currentSourceID == session.targetInputSourceID ||
                      currentSourceID == session.previousInputSourceID
                else {
                    logger("VOICE INPUT session_rejected reason=source_changed")
                    return false
                }
                session.owners.insert(owner)
                managedInputSourceSession = session
                return true
            }
            if currentInputSourceID() == targetInputSourceID {
                session.owners.insert(owner)
                managedInputSourceSession = session
                return true
            }
            guard owner == .explicitVoice else {
                logger("VOICE INPUT session_rejected reason=source_changed")
                return false
            }
            session.owners.insert(owner)
            session.activationPending = true
            managedInputSourceSession = session
            return completeExplicitActivation(
                targetInputSourceID: targetInputSourceID,
                activationShouldContinue: activationShouldContinue,
                selectedVoiceTool: selectedVoiceTool
            )
        }

        let previousInputSourceID = currentInputSourceID()
        if previousInputSourceID == targetInputSourceID {
            logger(
                "VOICE INPUT source_prepare tool=\(selectedVoiceTool.rawValue) result=selected managed=false"
            )
            return true
        }

        let result = prepareInputSource(selectedVoiceTool)
        logger(
            "VOICE INPUT source_prepare tool=\(selectedVoiceTool.rawValue) result=\(result.rawValue) " +
                "managed=\(result == .selected && previousInputSourceID != nil)"
        )
        guard result == .selected else { return false }
        managedInputSourceSession = ManagedInputSourceSession(
            previousInputSourceID: previousInputSourceID,
            targetInputSourceID: targetInputSourceID,
            owners: [owner],
            activationPending: owner == .explicitVoice
        )
        if owner == .explicitVoice {
            return completeExplicitActivation(
                targetInputSourceID: targetInputSourceID,
                activationShouldContinue: activationShouldContinue,
                selectedVoiceTool: selectedVoiceTool
            )
        }
        return true
    }

    private func completeExplicitActivation(
        targetInputSourceID: String,
        activationShouldContinue: () -> Bool,
        selectedVoiceTool: OnboardingVoiceTool
    ) -> Bool {
        let activated = waitForInputSourceActivation(
            targetInputSourceID,
            currentInputSourceID,
            activationShouldContinue
        )
        guard activated, activationShouldContinue() else {
            let activationResult = activationShouldContinue()
                ? "activation_timeout"
                : "activation_cancelled"
            logger(
                "VOICE INPUT source_prepare tool=\(selectedVoiceTool.rawValue) " +
                    "result=\(activationResult)"
            )
            // Cancellation already released this owner. Do not alter a newer
            // session that may have begun while the main run loop was pumped.
            guard activationShouldContinue() else { return false }
            if var session = managedInputSourceSession {
                session.activationPending = false
                managedInputSourceSession = session
            }
            finishManagedInputSourceSession(
                reason: activationResult,
                owner: .explicitVoice
            )
            return false
        }
        guard var session = managedInputSourceSession,
              session.owners.contains(.explicitVoice),
              session.targetInputSourceID == targetInputSourceID
        else {
            if var abandoned = managedInputSourceSession {
                abandoned.activationPending = false
                managedInputSourceSession = abandoned
            }
            finishManagedInputSourceSession(reason: "activation_session_changed", owner: .explicitVoice)
            return false
        }
        session.activationPending = false
        managedInputSourceSession = session
        logger("VOICE INPUT source_activation tool=\(selectedVoiceTool.rawValue) result=confirmed")
        return true
    }

    private func finishManagedInputSourceSession(
        reason: String,
        owner: ManagedInputSourceSession.Owner?
    ) {
        guard var session = managedInputSourceSession else { return }
        if let owner {
            session.owners.remove(owner)
            guard session.owners.isEmpty else {
                managedInputSourceSession = session
                return
            }
        }
        managedInputSourceSession = nil

        // CGEvent submission is not acknowledgment that the input method has
        // committed its result. Switching away at key-up (or on monitor stop)
        // can detach pending composition from the focused text client. Leave
        // selection to the user instead of guessing a recognition timeout.
        guard !session.voiceTriggerSubmitted else {
            logger("VOICE INPUT source_retained reason=composition_may_be_pending session_reason=\(reason)")
            return
        }

        guard let previousInputSourceID = session.previousInputSourceID else { return }
        let currentSourceID = currentInputSourceID()
        guard currentSourceID == session.targetInputSourceID ||
              currentSourceID == previousInputSourceID
        else {
            logger(
                "VOICE INPUT source_restore skipped reason=user_changed session_reason=\(reason)"
            )
            return
        }

        let result = restoreInputSource(previousInputSourceID)
        logger(
            "VOICE INPUT source_restore result=\(result.rawValue) reason=\(reason)"
        )
    }

    deinit {
        stop()
    }
}

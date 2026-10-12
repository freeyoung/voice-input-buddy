import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func performPhoneCommand(
        _ button: RemoteButton,
        source: RemoteInputSource,
        phraseSource: String? = nil
    ) -> Bool {
        guard source != .nearbyPhone || membershipFeature.canStartCompanionConnection else {
            disablePhoneRemoteConnection()
            return false
        }
        if OnboardingControlValidationPolicy.suppressConfiguredActions(
            at: settings.onboardingStep,
            source: settings.onboardingControlSource
        ) {
            AppLogger.shared.write(
                "ONBOARDING CONTROLS button=\(button.rawValue) source=\(source.rawValue) action=suppressed"
            )
            return true
        }
        if !macroFeature.isEditorActive,
           commonPhrases.claims(button, source: phraseSource ?? "mobile:\(source.rawValue)") {
            _ = commonPhrases.handle(button, phase: .press, source: phraseSource ?? "mobile:\(source.rawValue)")
            _ = commonPhrases.handle(button, phase: .release, source: phraseSource ?? "mobile:\(source.rawValue)")
            return true
        }
        return performMobileConfiguredAction(for: button, trigger: .singleClick, source: source, phraseSource: phraseSource)
    }

    func observeMobileButton(_ button: RemoteButton, source: RemoteInputSource) {
        lastMobileRemoteButtonObservation = MobileRemoteButtonObservation(
            source: source,
            button: button
        )
    }

    func handleMobileButtonEvent(
        _ button: RemoteButton,
        phase: RemoteButtonPhase,
        source: RemoteInputSource,
        phraseSource: String? = nil
    ) -> Bool {
        if phase == .press && source == .nearbyPhone && !membershipFeature.canStartCompanionConnection {
            disablePhoneRemoteConnection()
            return false
        }
        if OnboardingControlValidationPolicy.suppressConfiguredActions(
            at: settings.onboardingStep,
            source: settings.onboardingControlSource
        ) {
            if phase == .press {
                AppLogger.shared.write(
                    "ONBOARDING CONTROLS button=\(button.rawValue) source=\(source.rawValue) action=suppressed"
                )
            }
            return true
        }
        if macroFeature.isEditorActive {
            if phase == .press {
                macroFeature.noteButtonInteraction(button: button)
            }
            AppLogger.shared.write(
                "PHONE REMOTE button=\(button.rawValue) phase=\(phase.rawValue) " +
                    "path=binding_editor_capture"
            )
            return true
        }
        if commonPhrases.handle(button, phase: phase, source: phraseSource ?? "mobile:\(source.rawValue)") { return true }
        let profileID = settings.selectedRemoteProfileID
        let recognizesDoubleClick = settings.configuredAction(
            for: button,
            trigger: .doubleClick
        ).action != .disabled || macroFeature.hasActiveBinding(
            profileID: profileID,
            button: button,
            trigger: .doubleClick
        )
        let recognizesLongPress = settings.configuredAction(
            for: button,
            trigger: .longPress
        ).action != .disabled || macroFeature.hasActiveBinding(
            profileID: profileID,
            button: button,
            trigger: .longPress
        )

        var recognizer = mobileButtonGestureRecognizers[source] ?? RemoteButtonGestureRecognizer()
        if phase == .press,
           !recognizesDoubleClick,
           !recognizesLongPress,
           !recognizer.isTracking(button) {
            return performMobileConfiguredAction(
                for: button,
                trigger: .singleClick,
                source: source,
                phraseSource: phraseSource
            )
        }

        let commands = recognizer.handle(
            phase,
            button: button,
            recognizesDoubleClick: recognizesDoubleClick,
            recognizesLongPress: recognizesLongPress
        )
        mobileButtonGestureRecognizers[source] = recognizer
        return processMobileGestureCommands(commands, source: source, phraseSource: phraseSource)
    }

    private func processMobileGestureCommands(
        _ commands: [RemoteButtonGestureRecognizer.Command],
        source: RemoteInputSource,
        phraseSource: String? = nil
    ) -> Bool {
        for command in commands {
            switch command {
            case let .scheduleDoubleClickTimeout(button):
                scheduleMobileDoubleClickTimeout(for: button, source: source, phraseSource: phraseSource)
            case let .cancelDoubleClickTimeout(button):
                mobileDoubleClickTimers.removeValue(forKey: .init(
                    source: source,
                    button: button
                ))?.cancel()
            case let .scheduleLongPressTimeout(button):
                scheduleMobileLongPressTimeout(for: button, source: source, phraseSource: phraseSource)
            case let .cancelLongPressTimeout(button):
                mobileLongPressTimers.removeValue(forKey: .init(
                    source: source,
                    button: button
                ))?.cancel()
            case let .trigger(button, trigger):
                guard performMobileConfiguredAction(
                    for: button,
                    trigger: trigger,
                    source: source,
                    phraseSource: phraseSource
                ) else { return false }
            }
        }
        return true
    }

    private func scheduleMobileDoubleClickTimeout(
        for button: RemoteButton,
        source: RemoteInputSource,
        phraseSource: String? = nil
    ) {
        let key = MobileButtonGestureKey(source: source, button: button)
        mobileDoubleClickTimers.removeValue(forKey: key)?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            mobileDoubleClickTimers.removeValue(forKey: key)
            guard var recognizer = mobileButtonGestureRecognizers[source] else { return }
            let commands = recognizer.doubleClickTimedOut(button)
            mobileButtonGestureRecognizers[source] = recognizer
            _ = processMobileGestureCommands(commands, source: source, phraseSource: phraseSource)
        }
        mobileDoubleClickTimers[key] = timer
        timer.resume()
    }

    private func scheduleMobileLongPressTimeout(
        for button: RemoteButton,
        source: RemoteInputSource,
        phraseSource: String? = nil
    ) {
        let key = MobileButtonGestureKey(source: source, button: button)
        mobileLongPressTimers.removeValue(forKey: key)?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(550))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            mobileLongPressTimers.removeValue(forKey: key)
            guard var recognizer = mobileButtonGestureRecognizers[source] else { return }
            let commands = recognizer.longPressTimedOut(button)
            mobileButtonGestureRecognizers[source] = recognizer
            _ = processMobileGestureCommands(commands, source: source, phraseSource: phraseSource)
        }
        mobileLongPressTimers[key] = timer
        timer.resume()
    }

    func resetMobileButtonGestures(source: RemoteInputSource, phraseSource: String? = nil) {
        commonPhrases.reset(source: phraseSource ?? "mobile:\(source.rawValue)")
        let doubleClickKeys = mobileDoubleClickTimers.keys.filter { $0.source == source }
        doubleClickKeys.forEach {
            mobileDoubleClickTimers.removeValue(forKey: $0)?.cancel()
        }
        let longPressKeys = mobileLongPressTimers.keys.filter { $0.source == source }
        longPressKeys.forEach {
            mobileLongPressTimers.removeValue(forKey: $0)?.cancel()
        }
        mobileButtonGestureRecognizers.removeValue(forKey: source)
    }

    private func performMobileConfiguredAction(
        for button: RemoteButton,
        trigger: ButtonTrigger,
        source: RemoteInputSource,
        phraseSource: String? = nil
    ) -> Bool {
        if performButtonProfileBoundAction(
            profileID: settings.selectedRemoteProfileID,
            button: button,
            trigger: trigger,
            source: phraseSource ?? "mobile:\(source.rawValue)"
        ) {
            AppLogger.shared.write(
                "PHONE REMOTE button=\(button.rawValue) trigger=\(trigger.rawValue) action=private_feature"
            )
            return true
        }
        let configured = settings.configuredAction(for: button, trigger: trigger)
        if configured.action.isAppInternal {
            let handled = performInternalAction(configured.action, source: phraseSource ?? "mobile:\(source.rawValue)")
            AppLogger.shared.write(
                "PHONE REMOTE button=\(button.rawValue) trigger=\(trigger.rawValue) " +
                    "action=\(configured.action.rawValue) handled=\(handled)"
            )
            return handled
        }
        guard KeyboardInjector.isAccessibilityTrusted else {
            _ = KeyboardInjector.requestAccessibilityAccess()
            return false
        }
        guard performExternalConfiguredAction(configured) else {
            return false
        }
        AppLogger.shared.write(
            "PHONE REMOTE button=\(button.rawValue) trigger=\(trigger.rawValue) " +
                "action=\(configured.action.rawValue)"
        )
        return true
    }

    func performButtonProfileBoundAction(
        profileID: UUID?,
        button: RemoteButton,
        trigger: ButtonTrigger,
        source: String = "host_action"
    ) -> Bool {
        macroFeature.executeBoundAction(
            profileID: profileID,
            button: button,
            trigger: trigger,
            hostActionPerformer: { [weak self] payload in
                self?.performButtonProfileHostAction(payload, source: source) ?? false
            },
            shortcutPerformer: { [weak self] keyCode, modifiers in
                self?.performButtonProfileShortcut(keyCode: keyCode, modifiers: modifiers) ?? false
            }, exactShortcutPerformer: { [weak self] keyCode, modifiers, flags in
                self?.performButtonProfileShortcut(keyCode: keyCode, modifiers: modifiers, deviceModifierFlags: flags) ?? false
            }
        )
    }

    private func performButtonProfileHostAction(_ payload: Data, source: String) -> Bool {
        guard !macroFeature.hasPendingPortableImport else { return false }
        guard let configured = try? JSONDecoder().decode(ConfiguredButtonAction.self, from: payload)
        else { return false }
        if configured.action.isAppInternal {
            return performInternalAction(configured.action, source: source)
        }
        guard KeyboardInjector.isAccessibilityTrusted else {
            _ = KeyboardInjector.requestAccessibilityAccess()
            return false
        }
        return performExternalConfiguredAction(configured)
    }

    private func performButtonProfileShortcut(
        keyCode: UInt16,
        modifiers: [String], deviceModifierFlags: UInt64 = 0
    ) -> Bool {
        guard deviceModifierFlags & ~UInt64(0x207f) == 0 else { return false }
        var modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(deviceModifierFlags))
        for modifier in modifiers {
            switch modifier {
            case "command": modifierFlags.insert(.command)
            case "shift": modifierFlags.insert(.shift)
            case "option": modifierFlags.insert(.option)
            case "control": modifierFlags.insert(.control)
            case "function": modifierFlags.insert(.function)
            default: return false
            }
        }
        guard KeyboardInjector.isAccessibilityTrusted else {
            _ = KeyboardInjector.requestAccessibilityAccess()
            return false
        }
        return performExternalConfiguredAction(ConfiguredButtonAction(
            action: .customShortcut,
            shortcut: CustomKeyboardShortcut(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                keyLabel: "Key Code \(keyCode)"
            )
        ))
    }

    func performExternalConfiguredAction(_ configured: ConfiguredButtonAction) -> Bool {
        guard !macroFeature.hasPendingPortableImport else { return false }
        if configured.action == .combinationAction {
            return macroFeature.executeMacro(id: configured.macroID)
        }
        let applicationProfile = settings.customApplicationProfile(
            id: configured.applicationProfileID
        )
        if configured.action == .openCustomApplication {
            guard let profile = applicationProfile,
                !settings.portableApplicationRequiresVerification(profile),
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.bundleIdentifier) != nil
            else { return false }
        }
        let requestID = settings.voiceFnTapModeEnabled
            ? VoiceInputDestinationIntent.resolve(
                configured: configured,
                applicationProfile: applicationProfile
            ).map { voiceInputDestinationCoordinator.beginTargetSwitch(intent: $0) }
            : nil
        let handled = KeyboardInjector.send(
            configured.action,
            shortcut: configured.shortcut,
            applicationProfile: applicationProfile,
            focusInputCompletion: { [weak self] succeeded in
                if let requestID {
                    self?.voiceInputDestinationCoordinator.completeFocusOperation(requestID: requestID, succeeded: succeeded)
                }
            }
        )
        if !handled, let requestID {
            voiceInputDestinationCoordinator.cancel(requestID: requestID, reason: .actionFailed)
        }
        return handled
    }

    func handleVoiceInputDestinationState(_ state: VoiceInputDestinationState) {
        guard settings.voiceFnTapModeEnabled else { return }
        switch state {
        case .waiting:
            voiceShortcutStatus = LocalizedMessage("voice_button.status.waiting_for_input")
        case .ready:
            voiceShortcutStatus = LocalizedMessage("voice_button.status.input_ready")
        case .cancelled:
            voiceShortcutStatus = LocalizedMessage("voice_button.status.input_unavailable")
        }
    }

    static func commonPhraseHIDSource(_ profileID: UUID?) -> String {
        "hid:\(profileID?.uuidString ?? "unassigned")"
    }

    func cancelPendingCommonPhraseButtonActions() {
        hidMonitors.values.forEach { $0.cancelPendingButtonActions() }
        discoveryHIDMonitor?.cancelPendingButtonActions()
        mobileDoubleClickTimers.values.forEach { $0.cancel() }
        mobileDoubleClickTimers.removeAll()
        mobileLongPressTimers.values.forEach { $0.cancel() }
        mobileLongPressTimers.removeAll()
        mobileButtonGestureRecognizers.removeAll()
        appleRemoteDoubleClickTimers.values.forEach { $0.cancel() }
        appleRemoteDoubleClickTimers.removeAll()
        appleRemoteLongPressTimers.values.forEach { $0.cancel() }
        appleRemoteLongPressTimers.removeAll()
        appleRemoteGestureRecognizers.removeAll()
        appleRemoteRepeatTimers.values.forEach { $0.cancel() }
        appleRemoteRepeatTimers.removeAll()
        chromecastDoubleClickTimers.values.forEach { $0.cancel() }
        chromecastDoubleClickTimers.removeAll()
        chromecastLongPressTimers.values.forEach { $0.cancel() }
        chromecastLongPressTimers.removeAll()
        chromecastButtonGestureRecognizer.reset()
        if appleRemoteAppSwitcherSession.isActive {
            finishAppleRemoteAppSwitcher(reason: "common_phrases_opened", confirmed: false)
        }
    }

    @discardableResult
    func performInternalAction(_ action: ButtonAction, source: String = "host_action") -> Bool {
        if action == .openCommonPhrases {
            return commonPhrases.open(source: source, localization: LocalizationStore(settings: settings))
        }
        guard action == .toggleLongRecording else { return false }
        guard action.isEnabled(
            experimentalContinuousRecordingEnabled: settings.experimentalContinuousRecordingEnabled
        ) else {
            AppLogger.shared.write("LONG RECORDING ignored feature_enabled=false")
            return false
        }
        return toggleLongRecording()
    }
}

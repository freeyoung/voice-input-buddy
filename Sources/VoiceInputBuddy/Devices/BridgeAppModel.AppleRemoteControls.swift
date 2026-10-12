import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    private func handleAppleRemoteConnection(_ connection: SiriRemoteConnection) {
        if connection.isConnected {
            let profileID = settings.profileID(forHIDFingerprint: connection.fingerprint)
                ?? settings.registerAppleSiriRemote(
                    fingerprint: connection.fingerprint,
                    model: connection.model
                )
            settings.updateRemoteProfileModel(profileID, model: connection.model)
            appleRemoteProfileIDs[connection.device] = profileID
            connectedAppleRemoteProfileIDs.insert(profileID)
            if appleRemoteActiveButtons[connection.device] == nil {
                appleRemoteActiveButtons[connection.device] = []
            }
            if appleRemoteActiveControlIDs[connection.device] == nil {
                appleRemoteActiveControlIDs[connection.device] = []
            }
            AppLogger.shared.write(
                "APPLE REMOTE CONNECTION phase=completed result=connected " +
                    "model=\(connection.model.rawValue) " +
                    "connected_devices=\(connectedAppleRemoteProfileIDs.count)"
            )
        } else {
            if let profileID = appleRemoteProfileIDs.removeValue(forKey: connection.device) {
                commonPhrases.reset(source: "apple:\(profileID.uuidString)")
                connectedAppleRemoteProfileIDs.remove(profileID)
                remoteBatteryLevels.removeValue(forKey: profileID)
                remotePowerStates.removeValue(forKey: profileID)
            }
            resetAppleRemoteState(for: connection.device, reason: "device_disconnected")
            AppLogger.shared.write(
                "APPLE REMOTE CONNECTION phase=completed result=disconnected " +
                    "model=\(connection.model.rawValue) " +
                    "connected_devices=\(connectedAppleRemoteProfileIDs.count)"
            )
        }
        refreshAppleRemoteActiveButtons()
        refreshAppleRemoteActiveControlIDs()
        refreshAppleRemoteHIDStatus()
        refreshBluetoothPresentation()
        if connection.isConnected { refreshRemoteDeviceNames(reason: .connection) }
    }

    private func handleAppleRemotePowerSnapshot(_ snapshot: SiriRemotePowerSnapshot) {
        guard let profileID = appleRemoteProfileIDs[snapshot.device] else {
            AppLogger.shared.write(
                "APPLE REMOTE POWER_BRIDGE phase=ignored result=profile_unavailable " +
                    "model=\(snapshot.model.rawValue) availability=\(snapshot.availability.rawValue)"
            )
            return
        }
        if snapshot.availability == .available {
            if let level = snapshot.level {
                remoteBatteryLevels[profileID] = min(100, max(0, level))
            } else {
                remoteBatteryLevels.removeValue(forKey: profileID)
            }
            remotePowerStates[profileID] = snapshot.powerState
        } else {
            remoteBatteryLevels.removeValue(forKey: profileID)
            remotePowerStates.removeValue(forKey: profileID)
        }
        AppLogger.shared.write(
            "APPLE REMOTE POWER_BRIDGE phase=completed result=\(snapshot.availability.rawValue) " +
                "model=\(snapshot.model.rawValue) " +
                "level=\(snapshot.level.map(String.init) ?? "unknown") " +
                "state=\(snapshot.powerState.logValue) source=\(snapshot.source)"
        )
    }

    private func handleAppleRemoteControlEvent(_ event: SiriRemoteControlEvent) {
        let control = event.control
        if event.phase == .cancelled {
            resetAppleRemoteState(
                for: event.device,
                reason: event.cancellationReason ?? "unknown"
            )
            return
        }
        let suppressConfiguredAction = OnboardingControlValidationPolicy
            .suppressConfiguredActions(
                at: settings.onboardingStep,
                source: settings.onboardingControlSource
            )
        if suppressConfiguredAction, control == .siri {
            AppLogger.shared.write(
                "ONBOARDING CONTROLS button=siri source=apple_remote action=suppressed"
            )
            return
        }
        if control == .siri {
            guard let profileID = appleRemoteProfileIDs[event.device] else {
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=failed result=profile_unavailable"
                )
                return
            }
            if event.phase == .began {
                selectRemoteProfile(profileID)
            }
            var activeControlIDs = appleRemoteActiveControlIDs[event.device, default: []]
            if event.phase == .began {
                activeControlIDs.insert(control.rawValue)
            } else {
                activeControlIDs.remove(control.rawValue)
            }
            appleRemoteActiveControlIDs[event.device] = activeControlIDs
            refreshAppleRemoteActiveControlIDs()
            switch event.phase {
            case .began:
                beginAppleRemoteVoice(for: event.device)
            case .ended:
                endAppleRemoteVoice(for: event.device, reason: "released")
            case .cancelled:
                break
            }
            return
        }
        if control == .select {
            let nativeEdge: RemoteEventEdge = event.phase == .began ? .down : .up
            if !suppressConfiguredAction,
               event.phase == .began,
               siriRemoteCursorFeedback.activateHoveredElementIfAvailable() {
                appleRemoteHoverClickDevices.insert(event.device)
                hidEventSuppressor.arm(nativeEvents: control.nativeEvents, edge: nativeEdge)
                AppLogger.shared.write(
                    "APPLE REMOTE HOVER_CLICK phase=began result=activated action=ax_press"
                )
                return
            }
            if !suppressConfiguredAction,
               event.phase == .ended,
               appleRemoteHoverClickDevices.remove(event.device) != nil {
                hidEventSuppressor.arm(nativeEvents: control.nativeEvents, edge: nativeEdge)
                AppLogger.shared.write(
                    "APPLE REMOTE HOVER_CLICK phase=ended result=consumed"
                )
                return
            }
        }
        guard settings.customMappingEnabled || suppressConfiguredAction else {
            if event.phase == .began {
                AppLogger.shared.write(
                    "APPLE REMOTE ACTION phase=completed result=system_managed " +
                        "control=\(control.rawValue)"
                )
            }
            return
        }
        guard let profileID = appleRemoteProfileIDs[event.device] else {
            AppLogger.shared.write(
                "APPLE REMOTE ACTION phase=failed result=profile_unavailable " +
                    "control=\(control.rawValue)"
            )
            return
        }
        if event.phase == .began {
            selectRemoteProfile(profileID)
        }
        var activeControlIDs = appleRemoteActiveControlIDs[event.device, default: []]
        if event.phase == .began {
            activeControlIDs.insert(control.rawValue)
        } else {
            activeControlIDs.remove(control.rawValue)
        }
        appleRemoteActiveControlIDs[event.device] = activeControlIDs
        refreshAppleRemoteActiveControlIDs()
        guard let button = control.remoteButton else {
            if event.phase == .began {
                AppLogger.shared.write(
                    "APPLE REMOTE ACTION phase=completed result=unmapped " +
                        "control=\(control.rawValue)"
                )
            }
            return
        }
        let nativeEdge: RemoteEventEdge = event.phase == .began ? .down : .up
        hidEventSuppressor.arm(nativeEvents: control.nativeEvents, edge: nativeEdge)
        AppLogger.shared.write(
            "APPLE REMOTE NATIVE_EVENT phase=armed control=\(control.rawValue) " +
                "edge=\(nativeEdge == .down ? "down" : "up") " +
                "candidates=\(control.nativeEvents.count)"
        )
        handleAppleRemoteButton(
            button,
            phase: event.phase == .began ? .press : .release,
            device: event.device,
            profileID: profileID
        )
    }

    private func handleAppleRemoteButton(
        _ button: RemoteButton,
        phase: RemoteButtonPhase,
        device: SiriRemoteDeviceIdentity,
        profileID: UUID
    ) {
        if phase == .release {
            cancelAppleRemoteRepeat(
                for: button,
                device: device,
                reason: "released"
            )
        }
        var buttons = appleRemoteActiveButtons[device, default: []]
        if phase == .press {
            buttons.insert(button)
            lastRemoteButtonPress = button
        } else {
            buttons.remove(button)
        }
        appleRemoteActiveButtons[device] = buttons
        refreshAppleRemoteActiveButtons()

        if OnboardingControlValidationPolicy.suppressConfiguredActions(
            at: settings.onboardingStep,
            source: settings.onboardingControlSource
        ) {
            if phase == .press {
                AppLogger.shared.write(
                    "ONBOARDING CONTROLS button=\(button.rawValue) source=apple_remote action=suppressed"
                )
            }
            return
        }

        if !macroFeature.isEditorActive,
           commonPhrases.handle(button, phase: phase, source: "apple:\(profileID.uuidString)") { return }

        if appleRemoteAppSwitcherSession.isActive {
            if phase == .release {
                AppLogger.shared.write(
                    "APPLE REMOTE APP SWITCHER " +
                        "operation_id=\(appleRemoteAppSwitcherOperationLabel) " +
                        "phase=release_ignored button=\(button.rawValue)"
                )
                return
            }
            if handleAppleRemoteAppSwitcherControlPress(button) {
                return
            }
            finishAppleRemoteAppSwitcher(
                reason: "unrelated_button_\(button.rawValue)",
                confirmed: false
            )
        }

        if macroFeature.isEditorActive {
            if phase == .press {
                macroFeature.noteButtonInteraction(button: button)
            }
            AppLogger.shared.write(
                "APPLE REMOTE BUTTON phase=\(phase.rawValue) button=\(button.rawValue) " +
                    "path=binding_editor_capture"
            )
            return
        }

        let recognizesDoubleClick = settings.configuredAction(
            for: button,
            trigger: .doubleClick,
            profileID: profileID
        ).action != .disabled || macroFeature.hasActiveBinding(
            profileID: profileID,
            button: button,
            trigger: .doubleClick
        )
        let recognizesLongPress = settings.configuredAction(
            for: button,
            trigger: .longPress,
            profileID: profileID
        ).action != .disabled || macroFeature.hasActiveBinding(
            profileID: profileID,
            button: button,
            trigger: .longPress
        )
        var recognizer = appleRemoteGestureRecognizers[device]
            ?? RemoteButtonGestureRecognizer()
        if phase == .press,
           !recognizesDoubleClick,
           !recognizesLongPress,
           !recognizer.isTracking(button) {
            let handled = performAppleRemoteConfiguredAction(
                for: button,
                trigger: .singleClick,
                profileID: profileID
            )
            if handled {
                startAppleRemoteRepeatIfNeeded(
                    for: button,
                    device: device,
                    profileID: profileID
                )
            }
            return
        }
        let commands = recognizer.handle(
            phase,
            button: button,
            recognizesDoubleClick: recognizesDoubleClick,
            recognizesLongPress: recognizesLongPress
        )
        appleRemoteGestureRecognizers[device] = recognizer
        _ = processAppleRemoteGestureCommands(commands, device: device, profileID: profileID)
    }

    private func startAppleRemoteRepeatIfNeeded(
        for button: RemoteButton,
        device: SiriRemoteDeviceIdentity,
        profileID: UUID
    ) {
        let configured = settings.configuredAction(
            for: button,
            trigger: .singleClick,
            profileID: profileID
        )
        let hasSecondaryAction = appleRemoteHasSecondaryAction(
            for: button,
            profileID: profileID
        )
        guard let interval = AppleRemoteInteractionPolicy.repeatIntervalMilliseconds(
            for: button,
            action: configured.action,
            hasSecondaryAction: hasSecondaryAction,
            hasSingleActionOverride: macroFeature.hasActiveBinding(
                profileID: profileID,
                button: button,
                trigger: .singleClick
            ),
            frontmostBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        ) else { return }

        let key = AppleRemoteButtonGestureKey(device: device, button: button)
        cancelAppleRemoteRepeat(for: button, device: device, reason: "replaced")
        appleRemoteRepeatOperationCounter &+= 1
        let operationID = appleRemoteRepeatOperationCounter
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + .milliseconds(Int(HIDRemoteTiming.repeatStartMilliseconds)),
            repeating: .milliseconds(Int(interval))
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.appleRemoteActiveButtons[device]?.contains(button) == true,
                  self.appleRemoteProfileIDs[device] == profileID
            else {
                self.cancelAppleRemoteRepeat(
                    for: button,
                    device: device,
                    reason: "input_inactive"
                )
                return
            }
            let current = self.settings.configuredAction(
                for: button,
                trigger: .singleClick,
                profileID: profileID
            )
            guard current == configured,
                  AppleRemoteInteractionPolicy.repeatIntervalMilliseconds(
                      for: button,
                      action: current.action,
                      hasSecondaryAction: self.appleRemoteHasSecondaryAction(
                          for: button,
                          profileID: profileID
                      ),
                      hasSingleActionOverride: self.macroFeature.hasActiveBinding(
                          profileID: profileID,
                          button: button,
                          trigger: .singleClick
                      ),
                      frontmostBundleIdentifier:
                          NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                  ) != nil
            else {
                self.cancelAppleRemoteRepeat(
                    for: button,
                    device: device,
                    reason: "configuration_changed"
                )
                return
            }
            guard KeyboardInjector.isAccessibilityTrusted else {
                _ = KeyboardInjector.requestAccessibilityAccess()
                self.cancelAppleRemoteRepeat(
                    for: button,
                    device: device,
                    reason: "accessibility_required"
                )
                return
            }
            guard self.performExternalConfiguredAction(current) else {
                self.cancelAppleRemoteRepeat(
                    for: button,
                    device: device,
                    reason: "submission_failed"
                )
                return
            }
            self.appleRemoteRepeatCounts[key, default: 0] += 1
        }
        appleRemoteRepeatTimers[key] = timer
        appleRemoteRepeatCounts[key] = 0
        appleRemoteRepeatOperationIDs[key] = operationID
        timer.resume()
        AppLogger.shared.write(
            "APPLE REMOTE REPEAT operation_id=\(operationID) phase=started result=scheduled " +
                "button=\(button.rawValue) action=\(configured.action.rawValue) " +
                "start_delay_ms=\(HIDRemoteTiming.repeatStartMilliseconds) interval_ms=\(interval)"
        )
    }

    func cancelAppleRemoteRepeat(
        for button: RemoteButton,
        device: SiriRemoteDeviceIdentity,
        reason: String
    ) {
        let key = AppleRemoteButtonGestureKey(device: device, button: button)
        guard let timer = appleRemoteRepeatTimers.removeValue(forKey: key) else { return }
        timer.cancel()
        let repeatCount = appleRemoteRepeatCounts.removeValue(forKey: key) ?? 0
        let operationID = appleRemoteRepeatOperationIDs.removeValue(forKey: key) ?? 0
        AppLogger.shared.write(
            "APPLE REMOTE REPEAT operation_id=\(operationID) phase=completed result=stopped " +
                "button=\(button.rawValue) reason=\(reason) repeat_count=\(repeatCount)"
        )
    }

    private func appleRemoteHasSecondaryAction(
        for button: RemoteButton,
        profileID: UUID
    ) -> Bool {
        settings.hasSecondaryAction(for: button, profileID: profileID) ||
            [.doubleClick, .longPress].contains { trigger in
                macroFeature.hasActiveBinding(
                    profileID: profileID,
                    button: button,
                    trigger: trigger
                )
            }
    }

    private func processAppleRemoteGestureCommands(
        _ commands: [RemoteButtonGestureRecognizer.Command],
        device: SiriRemoteDeviceIdentity,
        profileID: UUID
    ) -> Bool {
        for command in commands {
            switch command {
            case let .scheduleDoubleClickTimeout(button):
                scheduleAppleRemoteDoubleClickTimeout(
                    for: button,
                    device: device,
                    profileID: profileID
                )
            case let .cancelDoubleClickTimeout(button):
                appleRemoteDoubleClickTimers.removeValue(forKey: .init(
                    device: device,
                    button: button
                ))?.cancel()
            case let .scheduleLongPressTimeout(button):
                scheduleAppleRemoteLongPressTimeout(
                    for: button,
                    device: device,
                    profileID: profileID
                )
            case let .cancelLongPressTimeout(button):
                appleRemoteLongPressTimers.removeValue(forKey: .init(
                    device: device,
                    button: button
                ))?.cancel()
            case let .trigger(button, trigger):
                guard performAppleRemoteConfiguredAction(
                    for: button,
                    trigger: trigger,
                    profileID: profileID
                ) else { return false }
            }
        }
        return true
    }

    private func scheduleAppleRemoteDoubleClickTimeout(
        for button: RemoteButton,
        device: SiriRemoteDeviceIdentity,
        profileID: UUID
    ) {
        let key = AppleRemoteButtonGestureKey(device: device, button: button)
        appleRemoteDoubleClickTimers.removeValue(forKey: key)?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            appleRemoteDoubleClickTimers.removeValue(forKey: key)
            guard var recognizer = appleRemoteGestureRecognizers[device] else { return }
            let commands = recognizer.doubleClickTimedOut(button)
            appleRemoteGestureRecognizers[device] = recognizer
            _ = processAppleRemoteGestureCommands(
                commands,
                device: device,
                profileID: profileID
            )
        }
        appleRemoteDoubleClickTimers[key] = timer
        timer.resume()
    }

    private func scheduleAppleRemoteLongPressTimeout(
        for button: RemoteButton,
        device: SiriRemoteDeviceIdentity,
        profileID: UUID
    ) {
        let key = AppleRemoteButtonGestureKey(device: device, button: button)
        appleRemoteLongPressTimers.removeValue(forKey: key)?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(550))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            appleRemoteLongPressTimers.removeValue(forKey: key)
            guard var recognizer = appleRemoteGestureRecognizers[device] else { return }
            let commands = recognizer.longPressTimedOut(button)
            appleRemoteGestureRecognizers[device] = recognizer
            _ = processAppleRemoteGestureCommands(
                commands,
                device: device,
                profileID: profileID
            )
        }
        appleRemoteLongPressTimers[key] = timer
        timer.resume()
    }

    private func performAppleRemoteConfiguredAction(
        for button: RemoteButton,
        trigger: ButtonTrigger,
        profileID: UUID
    ) -> Bool {
        if performButtonProfileBoundAction(
            profileID: profileID,
            button: button,
            trigger: trigger,
            source: "apple:\(profileID.uuidString)"
        ) {
            AppLogger.shared.write(
                "APPLE REMOTE BUTTON phase=completed result=submitted " +
                    "button=\(button.rawValue) trigger=\(trigger.rawValue) action=private_feature"
            )
            return true
        }
        let configured = settings.configuredAction(
            for: button,
            trigger: trigger,
            profileID: profileID
        )
        if configured.action == .appSwitcher {
            return performAppleRemoteAppSwitcher(for: button, trigger: trigger, profileID: profileID)
        }
        let handled: Bool
        if configured.action.isAppInternal {
            handled = performInternalAction(configured.action, source: "apple:\(profileID.uuidString)")
        } else {
            guard KeyboardInjector.isAccessibilityTrusted else {
                _ = KeyboardInjector.requestAccessibilityAccess()
                AppLogger.shared.write(
                    "APPLE REMOTE BUTTON phase=failed result=accessibility_required " +
                        "button=\(button.rawValue) trigger=\(trigger.rawValue)"
                )
                return false
            }
            handled = performExternalConfiguredAction(configured)
        }
        AppLogger.shared.write(
            "APPLE REMOTE BUTTON phase=completed result=\(handled ? "submitted" : "failed") " +
                "button=\(button.rawValue) trigger=\(trigger.rawValue) " +
                "action=\(configured.action.rawValue)"
        )
        return handled
    }
}

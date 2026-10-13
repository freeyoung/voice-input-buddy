import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func applyHIDSettings(
        allowVoiceKeyModeFallback: Bool = true,
        restartSiriRemote: Bool = true
    ) {
        let permissionSnapshot = HIDPermissionSnapshot.current
        appliedHIDPermissionSnapshot = permissionSnapshot
        if !permissionSnapshot.inputMonitoringGranted || !permissionSnapshot.accessibilityGranted {
            // Detach input filtering before voice/HID configuration touches system services.
            stopHIDMonitors()
        }
        if !permissionSnapshot.accessibilityGranted {
            _ = releaseVoiceKeyIfNeeded()
        }
        if started, permissionSnapshot.inputMonitoringGranted {
            preferredInputSourceMonitor.start()
        } else {
            preferredInputSourceMonitor.stop(
                preservingExplicitVoiceSession: VoiceKeySessionPreservationPolicy
                    .shouldPreserveInputSourceSession(
                        latchHeld: voiceKeyLatch.isHeld,
                        heldMode: heldVoiceKeyMode,
                        pendingMode: pendingVoiceKeyMode
                    )
            )
        }
        if !settings.customMappingEnabled {
            stopLongRecording(reason: "mapping_disabled")
        }
        if !settings.experimentalContinuousRecordingEnabled {
            stopLongRecording(reason: "feature_disabled")
        }

        let requestedVoiceKeyMode = settings.voiceKeyMode
        let accessibilityGranted = KeyboardInjector.isAccessibilityTrusted
        let requestedFnTapMode = settings.voiceFnTapModeEnabled && requestedVoiceKeyMode == .function
        if settings.voiceFnTapModeEnabled != requestedFnTapMode {
            settings.voiceFnTapModeEnabled = requestedFnTapMode
        }
        if !requestedFnTapMode, voiceFnTapSession.requiresCleanupBeforeMapping {
            voiceFnTapSession.setEnabled(false) { [weak self] cleaned in
                guard cleaned else { return }
                self?.applyHIDSettings(
                    allowVoiceKeyModeFallback: allowVoiceKeyModeFallback,
                    restartSiriRemote: restartSiriRemote
                )
            }
            return
        }
        requestNextHIDPermissionIfNeeded(
            voiceFnTapModeRequested: requestedFnTapMode,
            voiceKeyModeRequested: requestedVoiceKeyMode
        )
        let canFallbackVoiceKeyMode = Self.canFallbackVoiceKeyMode(
            isStreaming: isStreaming,
            allowVoiceKeyModeFallback: allowVoiceKeyModeFallback
        )
        var powerKeySuppressed: Bool
        if requestedFnTapMode, accessibilityGranted {
            powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: true)
            if voiceFunctionMapper.isVoiceKeyNeutralized {
                voiceFnTapSession.setEnabled(true)
            } else if !canFallbackVoiceKeyMode, isStreaming {
                AppLogger.shared.write(
                    "VOICE FN TAP mode_preserved reason=voice_active_mapping_failed"
                )
            } else if !canFallbackVoiceKeyMode {
                AppLogger.shared.write(
                    "VOICE FN TAP mode_preserved reason=voice_start_mapping_failed"
                )
            } else if HIDMappingRecoveryPolicy.shouldPreserveFnTapPreferenceAfterMappingFailure(
                hasMatchingServices: voiceFunctionMapper.hasMatchingServices
            ) {
                voiceFnTapSession.setEnabled(false)
                AppLogger.shared.write(
                    "VOICE FN TAP mode_pending_mapping reason=no_matching_service"
                )
                scheduleHIDMappingRecoveryIfNeeded(
                    restartSiriRemote: restartSiriRemote
                )
            } else {
                settings.voiceFnTapModeEnabled = false
                voiceFnTapSession.setEnabled(false)
                powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: false)
            }
        } else if requestedVoiceKeyMode != .function {
            powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: true)
            if !voiceFunctionMapper.isVoiceKeyNeutralized {
                if voiceFunctionMapper.hasMatchingServices {
                    if isStreaming {
                        voiceShortcutStatus = LocalizedMessage("voice_button.status.waiting")
                        AppLogger.shared.write(
                            "VOICE KEY mode_preserved reason=voice_active_mapping_failed " +
                                "mode=\(requestedVoiceKeyMode.rawValue)"
                        )
                    } else if canFallbackVoiceKeyMode {
                        settings.voiceKeyMode = .function
                        powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: false)
                        AppLogger.shared.write(
                            "VOICE KEY mode_fallback reason=voice_mapping_failed " +
                                "mode=\(requestedVoiceKeyMode.rawValue)"
                        )
                    } else {
                        voiceShortcutStatus = LocalizedMessage("voice_button.status.waiting")
                        AppLogger.shared.write(
                            "VOICE KEY mode_preserved reason=voice_start_mapping_failed " +
                                "mode=\(requestedVoiceKeyMode.rawValue)"
                        )
                    }
                } else if !accessibilityGranted {
                    voiceShortcutStatus = LocalizedMessage(
                        "connection.voice_key_mode.command_permission"
                    )
                    AppLogger.shared.write(
                        "VOICE KEY mode_pending_permission_and_mapping " +
                            "mode=\(requestedVoiceKeyMode.rawValue)"
                    )
                } else {
                    voiceShortcutStatus = LocalizedMessage("voice_button.status.waiting")
                    AppLogger.shared.write(
                        "VOICE KEY mode_pending_mapping reason=no_matching_service " +
                            "mode=\(requestedVoiceKeyMode.rawValue)"
                    )
                }
            } else if !accessibilityGranted {
                voiceShortcutStatus = LocalizedMessage(
                    "connection.voice_key_mode.command_permission"
                )
                AppLogger.shared.write(
                    "VOICE KEY mode_pending_permission mode=\(requestedVoiceKeyMode.rawValue)"
                )
            }
        } else {
            if requestedFnTapMode {
                settings.voiceFnTapModeEnabled = false
            }
            voiceFnTapSession.setEnabled(false)
            powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: false)
        }
        startHIDMonitors(powerKeySuppressed: powerKeySuppressed)
        completeHIDMappingRecoveryIfNeeded()
        refreshVoiceKeyCompatibilityWarning()
    }

    func setSiriRemoteEnabled(_ enabled: Bool) {
        guard enabled || activePhysicalVoiceControlSource != .siriRemote else { return }
        settings.siriRemoteEnabled = enabled
        AppLogger.shared.write("SIRI REMOTE ACTIVATION phase=changed enabled=\(enabled)")
    }

    /// Call only from enable/retry controls, never from startup or device discovery.
    func prepareSiriRemoteFromUserAction() {
    }

    func scheduleHIDMappingRecoveryIfNeeded(
        restartSiriRemote: Bool = true
    ) {
        guard hidMappingRecoveryWorkItem == nil else { return }
        guard let delay = HIDMappingRecoveryPolicy.retryDelay(
            forAttempt: hidMappingRecoveryAttempt,
            started: started,
            readyBridgeCount: readyBluetoothBridgeCount,
            hasMatchingServices: voiceFunctionMapper.hasMatchingServices
        ) else {
            if started,
               readyBluetoothBridgeCount > 0,
               !voiceFunctionMapper.hasMatchingServices,
               hidMappingRecoveryAttempt == HIDMappingRecoveryPolicy.retryDelays.count {
                AppLogger.shared.write(
                    "HID MAPPING RECOVERY exhausted attempts=\(hidMappingRecoveryAttempt) " +
                        "ready_bridges=\(readyBluetoothBridgeCount)"
                )
            }
            return
        }

        let attempt = hidMappingRecoveryAttempt + 1
        hidMappingRecoveryAttempt = attempt
        hidMappingRecoveryGeneration &+= 1
        let generation = hidMappingRecoveryGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.hidMappingRecoveryGeneration == generation else { return }
            self.hidMappingRecoveryWorkItem = nil
            guard self.started,
                  self.readyBluetoothBridgeCount > 0,
                  !self.voiceFunctionMapper.hasMatchingServices
            else {
                self.cancelHIDMappingRecovery(reason: "conditions_changed")
                return
            }
            AppLogger.shared.write(
                "HID MAPPING RECOVERY applying attempt=\(attempt) " +
                    "ready_bridges=\(self.readyBluetoothBridgeCount)"
            )
            self.applyHIDSettings(restartSiriRemote: restartSiriRemote)
            if !self.voiceFunctionMapper.hasMatchingServices {
                self.scheduleHIDMappingRecoveryIfNeeded(
                    restartSiriRemote: restartSiriRemote
                )
            }
        }
        hidMappingRecoveryWorkItem = workItem
        AppLogger.shared.write(
            "HID MAPPING RECOVERY scheduled attempt=\(attempt) " +
                "delay_ms=\(Int(delay * 1_000)) ready_bridges=\(readyBluetoothBridgeCount)"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func completeHIDMappingRecoveryIfNeeded() {
        guard voiceFunctionMapper.hasMatchingServices,
              hidMappingRecoveryWorkItem != nil || hidMappingRecoveryAttempt > 0
        else { return }
        let attempts = hidMappingRecoveryAttempt
        hidMappingRecoveryGeneration &+= 1
        hidMappingRecoveryWorkItem?.cancel()
        hidMappingRecoveryWorkItem = nil
        hidMappingRecoveryAttempt = 0
        AppLogger.shared.write(
            "HID MAPPING RECOVERY completed attempts=\(attempts) " +
                "matched=\(voiceFunctionMapper.matchedServiceCount)"
        )
    }

    func cancelHIDMappingRecovery(reason: String) {
        guard hidMappingRecoveryWorkItem != nil || hidMappingRecoveryAttempt > 0 else { return }
        let attempts = hidMappingRecoveryAttempt
        hidMappingRecoveryGeneration &+= 1
        hidMappingRecoveryWorkItem?.cancel()
        hidMappingRecoveryWorkItem = nil
        hidMappingRecoveryAttempt = 0
        AppLogger.shared.write(
            "HID MAPPING RECOVERY cancelled reason=\(reason) attempts=\(attempts)"
        )
    }

    func startHIDMonitors(powerKeySuppressed: Bool) {
        stopHIDMonitors()
        let backOnlyMode = !settings.customMappingEnabled && (
            settings.onboardingControlMethod == .physicalRemote ||
            settings.onboardingRemoteAvailability == .hasRemote ||
            settings.remoteDeviceProfiles.contains { $0.hidFingerprint != nil }
        )
        hidPowerKeySuppressed = powerKeySuppressed
        hidAllowedLocationIDs = settings.customMappingEnabled
            ? voiceFunctionMapper.powerSuppressedLocationIDs
            : nil
        guard settings.customMappingEnabled || backOnlyMode else {
            hidStatus = LocalizedMessage("button_mapping.status.system_managed")
            return
        }
        if settings.customMappingEnabled { _ = hidEventSuppressor.start() }
        for profile in settings.remoteDeviceProfiles {
            // 苹果遥控器与 Chromecast 都由各自的私有链路驱动；它们的档案不能被小米 HID
            // 发现链路当成候选，否则会给一个不存在的小米设备建监视器。
            guard !profile.model.usesPrivateAdapter,
                  let fingerprint = profile.hidFingerprint
            else { continue }
            let monitor = makeHIDMonitor(
                profileID: profile.id,
                targetFingerprint: fingerprint
            )
            hidMonitors[fingerprint] = monitor
            monitor.start(
                powerKeySuppressed: powerKeySuppressed,
                allowedLocationIDs: hidAllowedLocationIDs,
                allowBackOnly: backOnlyMode
            )
        }
        startHIDDiscoveryIfNeeded(allowBackOnly: backOnlyMode)
    }

    func cancelButtonMappingInteractions(device: UUID?) {
        hidMonitors.values.filter { $0.profileID == device }.forEach { $0.cancelMappingInteractions() }
        if discoveryHIDMonitor?.profileID == device { discoveryHIDMonitor?.cancelMappingInteractions() }
        if settings.selectedRemoteProfileID == device {
            resetMobileButtonGestures(source: .nearbyPhone)
            resetMobileButtonGestures(source: .webRemote)
        }
        AppLogger.shared.write("BUTTON CONFIGURATION phase=completed result=interactions_cancelled")
    }

    func stopHIDMonitors() {
        // Detach the blocking event tap before any synchronous IOKit close.
        hidEventSuppressor.stop()
        hidMonitors.values.forEach { $0.stop() }
        discoveryHIDMonitor?.stop()
        hidMonitors.removeAll()
        discoveryHIDMonitor = nil
        activeRemoteButtons = []
    }

    private func startHIDDiscoveryIfNeeded(allowBackOnly: Bool = false) {
        guard (settings.customMappingEnabled || allowBackOnly), discoveryHIDMonitor == nil else { return }
        let monitor = makeHIDMonitor(
            profileID: nil,
            targetFingerprint: nil,
            excludedFingerprints: { [weak self] in
                guard let self else { return [] }
                return Set(self.hidMonitors.keys)
            }
        )
        discoveryHIDMonitor = monitor
        monitor.start(
            powerKeySuppressed: hidPowerKeySuppressed,
            allowedLocationIDs: hidAllowedLocationIDs,
            allowBackOnly: allowBackOnly
        )
    }

    private func makeHIDMonitor(
        profileID: UUID?,
        targetFingerprint: String?,
        excludedFingerprints: @escaping () -> Set<String> = { [] }
    ) -> HIDRemoteMonitor {
        let monitor = HIDRemoteMonitor(
            settings: settings,
            profileID: profileID,
            targetFingerprint: targetFingerprint,
            excludedFingerprints: excludedFingerprints,
            eventSuppressor: hidEventSuppressor,
            ownsEventSuppressor: false,
            actionPerformer: { [weak self] _, _, configured in
                self?.performExternalConfiguredAction(configured) ?? false
            },
            overrideActionPerformer: { [weak self] profileID, button, trigger in
                self?.performButtonProfileBoundAction(
                    profileID: profileID,
                    button: button,
                    trigger: trigger,
                    source: Self.commonPhraseHIDSource(profileID)
                ) == true
            },
            hasOverrideBinding: { [weak self] profileID, button, trigger in
                self?.macroFeature.hasActiveBinding(
                    profileID: profileID,
                    button: button,
                    trigger: trigger
                ) == true
            }
        )
        monitor.claimsRuntimeButton = { [weak self] profileID, button in
            self?.commonPhrases.claims(button, source: Self.commonPhraseHIDSource(profileID)) == true
        }
        monitor.onRuntimeButton = { [weak self] profileID, button, phase in
            self?.commonPhrases.handle(button, phase: phase, source: Self.commonPhraseHIDSource(profileID)) == true
        }
        monitor.onInputReset = { [weak self] profileID in
            self?.commonPhrases.reset(source: Self.commonPhraseHIDSource(profileID))
        }
        monitor.onStatus = { [weak self, weak monitor] value in
            guard let self, let monitor else { return }
            if self.settings.selectedRemoteProfile?.model.isAppleSiriRemote == true {
                return
            }
            if monitor.profileID == self.settings.selectedRemoteProfileID || monitor.profileID == nil {
                self.hidStatus = value
                self.refreshVoiceKeyCompatibilityWarning()
            }
        }
        monitor.onActiveButtons = { [weak self] profileID, buttons in
            guard let self, profileID == self.settings.selectedRemoteProfileID else { return }
            self.activeRemoteButtons = buttons
        }
        monitor.onButtonPressed = { [weak self, weak monitor] profileID, fingerprint, button in
            guard let self, let monitor else {
                return profileID.map { ($0, true) }
            }
            let existingProfileID = profileID
                ?? self.settings.profileID(forHIDFingerprint: fingerprint)
            let resolvedProfileID = existingProfileID
                ?? self.settings.registerHIDRemote(fingerprint: fingerprint)
            if resolvedProfileID == self.settings.selectedRemoteProfileID,
               self.macroFeature.isEditorActive {
                self.macroFeature.noteButtonInteraction(button: button)
            }
            let isNewBinding = existingProfileID == nil
            if isNewBinding {
                monitor.assignProfileID(resolvedProfileID)
                self.hidMonitors[fingerprint] = monitor
                if self.discoveryHIDMonitor === monitor {
                    self.discoveryHIDMonitor = nil
                    self.startHIDDiscoveryIfNeeded()
                }
            }
            self.selectRemoteProfile(resolvedProfileID)
            self.lastRemoteButtonPress = button
            if self.macroFeature.isEditorActive {
                AppLogger.shared.write(
                    "HID BUTTON button=\(button.rawValue) path=binding_editor_capture"
                )
            }
            let suppressConfiguredAction = OnboardingControlValidationPolicy
                .suppressConfiguredActions(
                    at: self.settings.onboardingStep,
                    source: self.settings.onboardingControlSource
                )
            if suppressConfiguredAction {
                AppLogger.shared.write(
                    "ONBOARDING CONTROLS button=\(button.rawValue) action=suppressed"
                )
            }
            return (
                resolvedProfileID,
                !self.macroFeature.isEditorActive && !suppressConfiguredAction
            )
        }
        monitor.onInternalAction = { [weak self] profileID, action in
            guard let self else { return }
            if let profileID { self.selectRemoteProfile(profileID) }
            self.performInternalAction(action, source: Self.commonPhraseHIDSource(profileID))
        }
        return monitor
    }
}

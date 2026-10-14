import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func bluetoothBridgeDeviceNameDidChange(_ bridge: XiaomiBluetoothBridge) {
        guard bluetoothBridges.values.contains(where: { $0 === bridge }) else { return }
        refreshRemoteDeviceNames(reason: .peripheralEvent)
    }

    private func cancelPendingBluetoothVoiceStart(for identifier: UUID) {
        guard pendingBluetoothVoiceStart.cancel(ifOwnedBy: identifier) else { return }
        pendingBluetoothVoiceStopRequested = false
    }

    func bluetoothBridgeDidStartVoice(_ bridge: XiaomiBluetoothBridge) {
        guard let identifier = bridge.deviceIdentifier else { return }
        if let pendingIdentifier = pendingBluetoothVoiceStart.identifier,
           pendingIdentifier != identifier {
            _ = bridge.requestMicrophoneClose()
            cancelPendingBluetoothVoiceStart(for: identifier)
            AppLogger.shared.write("ATVV STREAM rejected_busy reason=pending_start")
            return
        }
        let outputReadyAtStart = audioOutput.isReadyForTestTone
        if !outputReadyAtStart {
            let shouldStartConfiguration = pendingBluetoothVoiceStart.identifier == nil
            if shouldStartConfiguration {
                pendingBluetoothVoiceStart.begin(for: identifier)
            }
        }
        if identifier == activeBluetoothVoiceDeviceIdentifier, bluetoothVoiceActive {
            cancelPendingBluetoothVoiceStart(for: identifier)
            AppLogger.shared.write("ATVV STREAM ignored_duplicate_start")

            return
        }
        let isRC003Continuation = rc003VoiceExtensionTestEnabled &&
            rc003VoiceExtensionActive &&
            rc003VoiceExtensionAwaitingReopen &&
            rc003VoiceExtensionBridge === bridge
        if let activeBluetoothVoiceDeviceIdentifier,
           activeBluetoothVoiceDeviceIdentifier != identifier {
            _ = bridge.requestMicrophoneClose()
            cancelPendingBluetoothVoiceStart(for: identifier)
            AppLogger.shared.write("ATVV STREAM rejected_busy")

            return
        }
        let profileID = activateRemoteProfile(for: bridge)
        if settings.voiceKeyMode != .function || settings.voiceFnTapModeEnabled || requiresOrderedVoiceFn {
            applyHIDSettings(allowVoiceKeyModeFallback: false)
        }
        guard Self.canStartBluetoothVoice(
            mode: settings.voiceKeyMode,
            voiceFnTapModeEnabled: settings.voiceFnTapModeEnabled,
            isVoiceKeyNeutralized: voiceFunctionMapper.isVoiceKeyNeutralized,
            hasHardwareVoiceKey: bridge.identifiedModel?.isChromecastRemote != true,
            accessibilityGranted: KeyboardInjector.isAccessibilityTrusted,
            requiresOrderedFn: requiresOrderedVoiceFn
        ) else {
            _ = bridge.requestMicrophoneClose()
            cancelPendingBluetoothVoiceStart(for: identifier)
            AppLogger.shared.write(
                "ATVV STREAM rejected reason=voice_key_not_neutralized " +
                    "mode=\(settings.voiceKeyMode.rawValue)"
            )

            return
        }
        if outputReadyAtStart {
            guard ensureVirtualAudioOutputReady(reason: "bluetooth_voice_start") else {
                _ = bridge.requestMicrophoneClose()
                cancelPendingBluetoothVoiceStart(for: identifier)
                AppLogger.shared.write("ATVV STREAM rejected_audio_output")

                return
            }
        }
        let pendingStartAudio: [Int16]
        if outputReadyAtStart, pendingBluetoothVoiceStart.identifier == identifier {
            pendingStartAudio = pendingBluetoothVoiceStart.drain()
        } else {
            pendingStartAudio = []
        }
        pendingCommandVoiceAudio.cancel()
        activeBluetoothVoiceDeviceIdentifier = identifier
        loggedBluetoothVoiceAudioDeviceIdentifier = nil
        bluetoothVoiceActive = true
        guard updateVoiceKeyState(
            streaming: true,
            forceSoftware: requiresOrderedVoiceFn ||
                (bridge.identifiedModel?.isChromecastRemote == true && !settings.voiceFnTapModeEnabled),
            owner: .bluetooth
        ) else {
            _ = bridge.requestMicrophoneClose()
            bluetoothVoiceActive = false
            activeBluetoothVoiceDeviceIdentifier = nil
            pendingBluetoothVoiceStart.cancel()
            pendingBluetoothVoiceStopRequested = false
            AppLogger.shared.write(
                "ATVV STREAM rejected reason=voice_key mode=\(settings.voiceKeyMode.rawValue)"
            )

            return
        }
        let model = profileID
            .flatMap { id in settings.remoteDeviceProfiles.first(where: { $0.id == id })?.model }
            ?? .unknown
        bluetoothVoiceTraceCounter &+= 1
        activeBluetoothVoiceTraceID = bluetoothVoiceTraceCounter
        bluetoothVoiceTraceStartedAt = Date()
        bluetoothVoiceTraceModel = model
        bluetoothVoiceDecodedBatchCount = 0
        bluetoothVoiceDecodedSampleCount = 0
        resetCurrentVoiceSampleReceipt()
        bluetoothVoiceEnqueueFailureCount = 0
        bluetoothVoiceTraceRoute = "none"
        bluetoothVoiceTailDiagnostics.reset()
        AppLogger.shared.write(
            "ATVV STREAM accepted trace=\(bluetoothVoiceTraceCounter) model=\(model.rawValue)"
        )

        cancelVirtualAudioReleaseIfPending(trigger: "bluetooth_voice_start")
        if longRecordingRequested {
            longRecordingOpenTimer?.cancel()
            longRecordingOpenTimer = nil
            AppLogger.shared.write("LONG RECORDING started")
        }
        if isRC003Continuation {
            rc003VoiceExtensionAwaitingReopen = false
            rc003VoiceExtensionDidReceiveAudio = false
            rc003VoiceExtensionOpenTimer?.cancel()
            rc003VoiceExtensionOpenTimer = nil
            AppLogger.shared.write(
                "RC003 EXTENSION physical_segment_reopened trace=\(activeBluetoothVoiceTraceID ?? 0)"
            )
        } else {
            _ = voiceFnTapSession.startVoice()
            beginVoiceSessionIfNeeded()
            if rc003VoiceExtensionTestEnabled, bridge.identifiedModel?.isChromecastRemote != true {
                rc003VoiceExtensionActive = true
                rc003VoiceExtensionAwaitingReopen = false
                rc003VoiceExtensionDidReceiveAudio = false
                rc003VoiceExtensionBridge = bridge
                rc003VoiceExtensionGeneration &+= 1
                scheduleRC003VoiceExtensionDeadline(
                    generation: rc003VoiceExtensionGeneration
                )
                AppLogger.shared.write(
                    "RC003 EXTENSION test_started max_duration_s=\(Int(Self.rc003VoiceExtensionMaximumDuration))"
                )
            }
        }
        if !outputReadyAtStart {
            guard let operationID = pendingBluetoothVoiceStart.operationID else { return }
            AppLogger.shared.write(
                "SYSTEM AUDIO voice_start_recovery configured=pending " +
                    "suspended=\(systemAudioSuspensionState.isSuspended) " +
                    "reasons=\(systemAudioSuspensionState.diagnostic)"
            )
            ensureVirtualAudioOutputReady(reason: "bluetooth_voice_start") { [weak self, weak bridge] ready in
                guard let self, self.started,
                      self.pendingBluetoothVoiceStart.matches(
                        identifier: identifier, operationID: operationID
                      ) else { return }
                guard let bridge else {
                    self.pendingBluetoothVoiceStart.cancel(ifOwnedBy: identifier)
                    self.pendingBluetoothVoiceStopRequested = false
                    self.releaseVirtualAudioOutputIfUnused(reason: "bluetooth_source_released")
                    return
                }
                let stopRequested = self.pendingBluetoothVoiceStopRequested
                self.pendingBluetoothVoiceStopRequested = false
                let bufferedAudio = self.pendingBluetoothVoiceStart.drain()
                guard ready else {
                    self.pendingBluetoothVoiceStart.audio.cancel()
                    _ = bridge.requestMicrophoneClose()
                    AppLogger.shared.write("ATVV STREAM rejected_audio_output")
                    self.bluetoothBridgeDidStopVoice(bridge)
                    return
                }
                if !bufferedAudio.isEmpty {
                    AppLogger.shared.write(
                        "ATVV AUDIO flush_after_configuration samples=\(bufferedAudio.count)"
                    )
                    self.routeBluetoothVoiceSamples(
                        bufferedAudio,
                        from: bridge,
                        identifier: identifier
                    )
                }
                self.flushPendingCommandVoiceAudio(for: bridge)
                if stopRequested {
                    self.bluetoothBridgeDidStopVoice(bridge)
                }
            }
        }
        if !pendingStartAudio.isEmpty {
            AppLogger.shared.write(
                "ATVV AUDIO flush_after_configuration samples=\(pendingStartAudio.count)"
            )
            routeBluetoothVoiceSamples(
                pendingStartAudio,
                from: bridge,
                identifier: identifier
            )
        }
        if outputReadyAtStart {
            flushPendingCommandVoiceAudio(for: bridge)
        }
    }

    func bluetoothBridgeDidStopVoice(_ bridge: XiaomiBluetoothBridge) {
        guard let identifier = bridge.deviceIdentifier else { return }
        if pendingBluetoothVoiceStart.identifier == identifier,
           activeBluetoothVoiceDeviceIdentifier == nil {
            pendingBluetoothVoiceStart.cancel()
            pendingBluetoothVoiceStopRequested = false
            AppLogger.shared.write("ATVV STREAM stop_before_audio_ready result=cancelled")
            return
        }
        if pendingBluetoothVoiceStart.identifier == identifier {
            pendingBluetoothVoiceStopRequested = true
            AppLogger.shared.write(
                "ATVV STREAM stop_deferred_until_audio_ready result=pending_tail " +
                    "pending_samples=\(pendingBluetoothVoiceStart.audio.bufferedSampleCount)"
            )
            return
        }
        guard identifier == activeBluetoothVoiceDeviceIdentifier else { return }
        if rc003VoiceExtensionTestEnabled,
           rc003VoiceExtensionActive,
           rc003VoiceExtensionBridge === bridge {
            bluetoothVoiceActive = false
            loggedBluetoothVoiceAudioDeviceIdentifier = nil
            rc003VoiceExtensionAwaitingReopen = true
            rc003VoiceExtensionDidReceiveAudio = false
            rc003VoiceExtensionTimer?.cancel()
            rc003VoiceExtensionTimer = nil
            rc003VoiceExtensionGeneration &+= 1
            let opened = bridge.requestMicrophoneOpen()
            if opened {
                scheduleRC003VoiceExtensionOpenTimeout(
                    generation: rc003VoiceExtensionGeneration
                )
            } else {
                finishRC003VoiceExtensionTest(reason: "reopen_rejected")
            }
            AppLogger.shared.write(
                "RC003 EXTENSION physical_stop reopen_requested=\(opened) " +
                    "generation=\(rc003VoiceExtensionGeneration)"
            )
            return
        }
        activeBluetoothVoiceDeviceIdentifier = nil
        loggedBluetoothVoiceAudioDeviceIdentifier = nil
        bluetoothVoiceActive = false
        pendingBluetoothVoiceStart.cancel()
        pendingBluetoothVoiceStopRequested = false
        releaseVoiceKeyIfNeeded(owner: .bluetooth, forceSoftware: true)
        pendingCommandVoiceAudio.cancel()
        if longRecordingRequested {
            finishLongRecording(reason: "remote_stop")
        } else if longRecordingCloseTimer != nil {
            longRecordingCloseTimer?.cancel()
            longRecordingCloseTimer = nil
            AppLogger.shared.write("LONG RECORDING close_confirmed")
        }
        let handledByFnTapMode = voiceFnTapSession.stopVoice()
        let traceID = activeBluetoothVoiceTraceID ?? 0
        let durationMilliseconds = bluetoothVoiceTraceStartedAt.map {
            max(0, Int(Date().timeIntervalSince($0) * 1_000))
        } ?? 0
        let shouldFlushAudio = BluetoothVoiceStopPolicy.shouldFlushAudio(
            handledByFnTapMode: handledByFnTapMode
        )
        let pendingBuffers = audioOutput.pendingVoiceBufferCountForDiagnostics
        let tailSnapshot = bluetoothVoiceTailDiagnostics.snapshot(
            at: ProcessInfo.processInfo.systemUptime
        )
        AppLogger.shared.write(
            "ATVV STREAM summary trace=\(traceID) model=\(bluetoothVoiceTraceModel.rawValue) " +
                "duration_ms=\(durationMilliseconds) batches=\(bluetoothVoiceDecodedBatchCount) " +
                "samples=\(bluetoothVoiceDecodedSampleCount) " +
                "enqueue_failures=\(bluetoothVoiceEnqueueFailureCount) " +
                "route=\(bluetoothVoiceTraceRoute) pending_buffers=\(pendingBuffers) " +
                "flush=\(shouldFlushAudio) audio_ready=\(audioOutput.isReadyForTestTone) " +
                "audio_state={\(audioOutput.diagnosticState())}"
        )
        AppLogger.shared.write(
            "ATVV STREAM tail trace=\(traceID) model=\(bluetoothVoiceTraceModel.rawValue) " +
                "route=\(bluetoothVoiceTraceRoute) " +
                "fn_pressed_at_stop=\(preferredInputSourceMonitor.functionKeyIsPressedForDiagnostics) " +
                "last_audio_age_ms=\(tailSnapshot.lastAudioAgeMilliseconds.map(String.init) ?? "none") " +
                "tail_ms=\(tailSnapshot.durationMilliseconds) " +
                "tail_samples=\(tailSnapshot.sampleCount) " +
                "tail_nonzero=\(tailSnapshot.nonZeroSampleCount) " +
                "tail_peak=\(tailSnapshot.peak) tail_rms=\(tailSnapshot.rms) " +
                "final_window_ms=\(tailSnapshot.finalWindowDurationMilliseconds) " +
                "final_window_samples=\(tailSnapshot.finalWindowSampleCount) " +
                "final_window_nonzero=\(tailSnapshot.finalWindowNonZeroSampleCount) " +
                "final_window_peak=\(tailSnapshot.finalWindowPeak) " +
                "final_window_rms=\(tailSnapshot.finalWindowRMS)"
        )
        audioOutput.logWhenPendingVoiceAudioDrains(
            context: "trace=\(traceID) model=\(bluetoothVoiceTraceModel.rawValue)"
        )
        activeBluetoothVoiceTraceID = nil
        bluetoothVoiceTraceStartedAt = nil
        bluetoothVoiceTailDiagnostics.reset()
        endVoiceSessionIfNeeded(flushAudio: shouldFlushAudio)
        if systemAudioSuspensionState.isSuspended {
            releaseVirtualAudioOutputIfUnused(reason: "system_suspended_after_bluetooth_voice")
        }
    }

    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didDecode samples: [Int16]) {
        guard let identifier = bridge.deviceIdentifier else { return }
        if identifier == pendingBluetoothVoiceStart.identifier,
           pendingBluetoothVoiceStart.audio.appendIfWaiting(samples) {
            AppLogger.shared.write(
                "ATVV AUDIO buffered_during_configuration samples=\(samples.count) " +
                    "total=\(pendingBluetoothVoiceStart.audio.bufferedSampleCount)"
            )
            return
        }
        guard identifier == activeBluetoothVoiceDeviceIdentifier else { return }
        if pendingCommandVoiceAudio.appendIfWaiting(samples) {
            AppLogger.shared.write(
                "ATVV AUDIO buffered_before_command samples=\(samples.count) " +
                    "total=\(pendingCommandVoiceAudio.bufferedSampleCount)"
            )
            return
        }
        routeBluetoothVoiceSamples(samples, from: bridge, identifier: identifier)
    }

    private func flushPendingCommandVoiceAudio(for bridge: XiaomiBluetoothBridge) {
        let samples = pendingCommandVoiceAudio.drain()
        guard !samples.isEmpty, let identifier = bridge.deviceIdentifier else { return }
        AppLogger.shared.write("ATVV AUDIO flush_before_command samples=\(samples.count)")
        routeBluetoothVoiceSamples(samples, from: bridge, identifier: identifier)
    }

    private func routeBluetoothVoiceSamples(
        _ samples: [Int16],
        from bridge: XiaomiBluetoothBridge,
        identifier: UUID
    ) {
        guard identifier == activeBluetoothVoiceDeviceIdentifier else { return }
        let deliveryGeneration = voiceAudioDeliveryDiagnostic.generation
        let handledByFnTapMode = voiceFnTapSession.receive(samples)
        let enqueued: Bool
        if handledByFnTapMode {
            enqueued = true
        } else {
            enqueued = audioOutput.enqueue(
                samples: samples,
                deliveryGeneration: deliveryGeneration
            )
            recordVoiceAudioEnqueueOutcome(
                accepted: enqueued,
                deliveryGeneration: deliveryGeneration
            )
        }
        recordVoiceAudioReceipt(
            samples: samples,
            route: handledByFnTapMode ? .virtualAudioViaFnTap : .virtualAudioDirect
        )
        bluetoothVoiceDecodedBatchCount += 1
        bluetoothVoiceDecodedSampleCount += samples.count
        bluetoothVoiceTailDiagnostics.append(samples, at: ProcessInfo.processInfo.systemUptime)
        publishCurrentVoiceSampleReceiptIfNeeded(sampleCount: samples.count)
        if !enqueued {
            bluetoothVoiceEnqueueFailureCount += 1
        }
        bluetoothVoiceTraceRoute = handledByFnTapMode ? "fn_tap" : "virtual_audio"
        if loggedBluetoothVoiceAudioDeviceIdentifier != identifier {
            loggedBluetoothVoiceAudioDeviceIdentifier = identifier
            let model = settings.profileID(forBluetoothIdentifier: identifier)
                .flatMap { id in settings.remoteDeviceProfiles.first(where: { $0.id == id })?.model }
                ?? .unknown
            AppLogger.shared.write(
                "ATVV AUDIO routed trace=\(activeBluetoothVoiceTraceID ?? 0) " +
                    "model=\(model.rawValue) route=\(bluetoothVoiceTraceRoute) " +
                    "accepted=\(enqueued) first_batch_samples=\(samples.count) " +
                    "pending_buffers=\(audioOutput.pendingVoiceBufferCountForDiagnostics)"
            )
        }
        if rc003VoiceExtensionTestEnabled,
           rc003VoiceExtensionActive,
           rc003VoiceExtensionBridge === bridge,
           !rc003VoiceExtensionAwaitingReopen,
           !rc003VoiceExtensionDidReceiveAudio {
            rc003VoiceExtensionDidReceiveAudio = true
            startRC003VoiceExtensionTimer()
            AppLogger.shared.write(
                "RC003 EXTENSION AUDIO_READY session_segment=\(activeBluetoothVoiceTraceID ?? 0) " +
                    "samples=\(samples.count)"
            )
        }
    }

    func bluetoothBridge(_ bridge: XiaomiBluetoothBridge, didUpdateBatteryLevel level: Int?) {
        guard let profileID = remoteProfileID(for: bridge) else {
            if let identifier = bluetoothIdentifier(for: bridge) {
                pendingRemoteBatteryLevels[identifier] = level
                AppLogger.shared.write(
                    "REMOTE PROFILE_TELEMETRY phase=buffered " +
                        "result=\(level == nil ? "invalidated" : "deferred") " +
                        "reason=handshake_pending kind=battery"
                )
            }
            return
        }
        if let level {
            remoteBatteryLevels[profileID] = min(100, max(0, level))
        } else {
            remoteBatteryLevels.removeValue(forKey: profileID)
        }
    }

    func bluetoothBridge(
        _ bridge: XiaomiBluetoothBridge,
        didIdentifyRemoteModel model: XiaomiRemoteModel
    ) {
        guard let profileID = remoteProfileID(for: bridge) else {
            if let identifier = bluetoothIdentifier(for: bridge) {
                pendingRemoteModels[identifier] = model
                AppLogger.shared.write(
                    "REMOTE PROFILE_TELEMETRY phase=buffered result=deferred " +
                        "reason=handshake_pending kind=model"
                )
            }
            return
        }
        settings.updateRemoteProfileModel(profileID, model: model)
        learnSelectedRemoteHIDIdentity(bridge)
        refreshRemoteDeviceNames(reason: .connection)
    }

    func bluetoothBridge(
        _ bridge: XiaomiBluetoothBridge,
        didUpdatePowerState state: RemotePowerState?
    ) {
        guard let profileID = remoteProfileID(for: bridge) else {
            if let identifier = bluetoothIdentifier(for: bridge) {
                pendingRemotePowerStates[identifier] = state
                AppLogger.shared.write(
                    "REMOTE PROFILE_TELEMETRY phase=buffered " +
                        "result=\(state == nil ? "invalidated" : "deferred") " +
                        "reason=handshake_pending kind=power"
                )
            }
            return
        }
        if let state {
            remotePowerStates[profileID] = state
        } else {
            remotePowerStates.removeValue(forKey: profileID)
        }
    }

    func batteryLevel(for profileID: UUID) -> Int? {
        remoteBatteryLevels[profileID]
    }

    func powerState(for profileID: UUID) -> RemotePowerState? {
        remotePowerStates[profileID]
    }

    func systemDeviceName(for profile: RemoteDeviceProfile) -> String? {
        remoteSystemDeviceNames[profile.id]
            ?? RemoteDeviceNamePolicy.observedSystemName(from: profile.customName)
    }

#if DEBUG
    func configureRemoteCardsForSettingsScreenshot(
        profileIDs: Set<UUID>,
        systemNames: [UUID: String],
        batteryLevels: [UUID: Int],
        powerStates: [UUID: RemotePowerState]
    ) {
        guard ProcessInfo.processInfo.environment["VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_DIR"] != nil else {
            return
        }
        connectedRemoteProfileIDs = profileIDs
        remoteSystemDeviceNames = systemNames
        remoteBatteryLevels = batteryLevels
        remotePowerStates = powerStates
    }

#endif

    func isRemoteConnected(_ profileID: UUID) -> Bool {
        connectedRemoteProfileIDs.contains(profileID)
    }

    func bluetoothBridge(
        _ bridge: XiaomiBluetoothBridge,
        didChange state: BluetoothBridgeState
    ) {
        let bridgeObjectID = ObjectIdentifier(bridge)
        let previousState = bluetoothBridgeStates[bridgeObjectID]
        let shouldReapplyHIDSettings = Self.shouldReapplyHIDSettings(
            previousState: previousState,
            currentState: state
        )
        bluetoothBridgeStates[bridgeObjectID] = state
        if case .ready = state {
            _ = registerBluetoothBridgeIfNeeded(bridge)
            learnSelectedRemoteHIDIdentity(bridge)
            voiceFnTapSession.resume()
            if shouldReapplyHIDSettings {
                applyHIDSettings()
                scheduleHIDMappingRecoveryIfNeeded()
            }
        } else {
            if readyBluetoothBridgeCount == 0 {
                cancelHIDMappingRecovery(reason: "bluetooth_not_ready")
            }
            let identifier = bluetoothIdentifier(for: bridge)
            if let identifier {
                cancelPendingBluetoothVoiceStart(for: identifier)
                let hadBattery = pendingRemoteBatteryLevels.removeValue(forKey: identifier) != nil
                let hadPower = pendingRemotePowerStates.removeValue(forKey: identifier) != nil
                let hadModel = pendingRemoteModels.removeValue(forKey: identifier) != nil
                if hadBattery || hadPower || hadModel {
                    AppLogger.shared.write(
                        "REMOTE PROFILE_TELEMETRY phase=cancelled result=discarded " +
                            "reason=bridge_not_ready battery=\(hadBattery) " +
                            "power=\(hadPower) model=\(hadModel)"
                    )
                }
                if let profileID = settings.profileID(forBluetoothIdentifier: identifier) {
                    remoteBatteryLevels.removeValue(forKey: profileID)
                    remotePowerStates.removeValue(forKey: profileID)
                }
            }
            let voiceWasActive = BluetoothVoiceDeviceOwnershipPolicy.matches(identifier, active: activeBluetoothVoiceDeviceIdentifier)
            if voiceWasActive {
                if rc003VoiceExtensionTestEnabled,
                   rc003VoiceExtensionActive,
                   rc003VoiceExtensionBridge === bridge {
                    finishRC003VoiceExtensionTest(reason: "bluetooth_not_ready")
                }
                bluetoothVoiceActive = false
                activeBluetoothVoiceDeviceIdentifier = nil
                pendingCommandVoiceAudio.cancel()
                _ = voiceFnTapSession.stopVoice()
                releaseVoiceKeyIfNeeded(owner: .bluetooth, forceSoftware: true)
                endVoiceSessionIfNeeded(flushAudio: false)
            }
            if longRecordingRequested {
                finishLongRecording(reason: "bluetooth_not_ready")
            }
        }
        refreshBluetoothPresentation()
        if case .ready = state { refreshRemoteDeviceNames(reason: .connection) }
        if isConnected {
            voiceFnTapSession.resume()
            if shouldKeepVirtualAudioActive {
                cancelVirtualAudioReleaseIfPending(trigger: "bluetooth_ready")
                _ = ensureVirtualAudioOutputReady(reason: "bluetooth_ready")
            } else if !isAudioOutputReady {
                AppLogger.shared.write(
                    "AUDIO REBIND deferred reason=bluetooth_ready " +
                        "system_suspended=\(systemAudioSuspensionState.isSuspended) " +
                        "reasons=\(systemAudioSuspensionState.diagnostic)"
                )
            }
        } else {
            voiceFnTapSession.suspend { [weak self] _ in
                self?.releaseVirtualAudioOutputIfUnused(reason: "bluetooth_not_ready")
            }
        }
    }
}

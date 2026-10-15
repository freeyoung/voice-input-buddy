import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func endAppleRemoteVoice(
        for device: SiriRemoteDeviceIdentity,
        reason: String
    ) {
        if appleRemoteVoiceDevices.contains(device), pendingVoiceKeyActivationOwner == .appleRemote {
            appleRemoteVoiceDevices.remove(device)
            if appleRemoteVoiceDevices.isEmpty {
                _ = releaseVoiceKeyIfNeeded(owner: .appleRemote, forceSoftware: true)
            }
            return
        }
        if pendingAppleRemoteVoiceStarts.contains(device) {
            if appleRemoteVoiceDevices.contains(device) {
                pendingAppleRemoteVoiceStops.request(device)
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=deferred result=pending_tail " +
                        "reason=\(reason)"
                )
            } else {
                pendingAppleRemoteVoiceStarts.remove(device)
                pendingAppleRemoteVoiceStops.cancel(device)
                pendingAppleRemoteVoiceAudio.cancel()
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=completed result=cancelled_before_audio_ready " +
                        "reason=\(reason)"
                )
            }
            return
        }
        guard appleRemoteVoiceDevices.remove(device) != nil else { return }
        appleRemoteVoiceCaptureRetryWorkItem?.cancel()
        appleRemoteVoiceCaptureRetryWorkItem = nil
        if appleRemoteVoiceStopping {
            AppLogger.shared.write(
                "APPLE REMOTE VOICE phase=completed result=deferred_session_cancelled " +
                    "reason=\(reason)"
            )
            return
        }
        guard appleRemoteVoiceDevices.isEmpty else { return }
        appleRemoteVoiceStopping = true
        appleRemoteVoiceStopOperation &+= 1
        let stopOperation = appleRemoteVoiceStopOperation
        let deliveryGeneration = voiceAudioDeliveryDiagnostic.generation
        let outputBeforeStop = audioOutput.diagnosticSnapshot(
            deliveryGeneration: deliveryGeneration
        )
        appleRemoteAudioStopPendingBuffers = outputBeforeStop.pendingBuffers
        appleRemoteAudioStopPendingSamples = outputBeforeStop.pendingSamples
        AppLogger.shared.write(
            "APPLE REMOTE AUDIO playback_stop phase=waiting_for_capture_tail " +
                "reason=\(reason) generation=\(deliveryGeneration) " +
                "pending_buffers=\(outputBeforeStop.pendingBuffers) " +
                "pending_samples=\(outputBeforeStop.pendingSamples)"
        )
        siriRemoteFeature.stopCapture { [weak self] in
            guard let self,
                  self.appleRemoteVoiceStopping,
                  self.appleRemoteVoiceStopOperation == stopOperation
            else { return }
            self.audioOutput.endSessionAfterDraining(
                source: "apple_remote",
                operationID: stopOperation,
                maximumDelay: 2
            ) { [weak self] outcome in
                self?.completeAppleRemoteVoiceStop(
                    operation: stopOperation,
                    deliveryGeneration: deliveryGeneration,
                    reason: reason,
                    drainOutcome: outcome
                )
            }
        }
    }

    func scheduleAppleRemoteVoiceCaptureRetry(
        for device: SiriRemoteDeviceIdentity
    ) {
        guard appleRemoteVoiceCaptureRetryWorkItem == nil else { return }
        let delays: [TimeInterval] = [0.1, 0.25, 0.5, 1.0, 2.0]
        guard appleRemoteVoiceCaptureRetryAttempt < delays.count else {
            AppLogger.shared.write(
                "APPLE REMOTE VOICE phase=failed result=audio_capture_retry_exhausted " +
                    "attempts=\(appleRemoteVoiceCaptureRetryAttempt)"
            )
            return
        }
        let attempt = appleRemoteVoiceCaptureRetryAttempt
        appleRemoteVoiceCaptureRetryAttempt += 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.appleRemoteVoiceCaptureRetryWorkItem = nil
            guard self.appleRemoteVoiceDevices.contains(device),
                  !self.appleRemoteVoiceStopping
            else { return }
            if self.siriRemoteFeature.beginCapture() {
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=started result=retry_succeeded " +
                        "retry_attempt=\(attempt + 1) audio_source=apple_remote_microphone " +
                        "route=BuddyMic2ch"
                )
                return
            }
            AppLogger.shared.write(
                "APPLE REMOTE VOICE phase=pending result=retry_not_ready " +
                    "retry_attempt=\(attempt + 1)"
            )
            self.scheduleAppleRemoteVoiceCaptureRetry(for: device)
        }
        appleRemoteVoiceCaptureRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt], execute: workItem)
    }

    private func completeAppleRemoteVoiceStop(
        operation: UInt64,
        deliveryGeneration: Int,
        reason: String,
        drainOutcome: VirtualAudioDrainOutcome
    ) {
        guard appleRemoteVoiceStopping,
              appleRemoteVoiceStopOperation == operation
        else { return }
        let deferredDevices = appleRemoteVoiceDevices
        appleRemoteVoiceDevices.removeAll()
        let released = releaseVoiceKeyIfNeeded(owner: .appleRemote, forceSoftware: true)
        appleRemoteVoiceStopping = false
        siriRemoteFeature.setVoiceTouchSuppressed(false)
        endVoiceSessionIfNeeded(flushAudio: false)
        let outputAfterStop = audioOutput.diagnosticSnapshot(
            deliveryGeneration: deliveryGeneration
        )
        appleRemoteAudioStopInterruptedBuffers = outputAfterStop.counters.interruptedBuffers
        appleRemoteAudioStopInterruptedSamples = outputAfterStop.counters.interruptedSamples
        voiceAudioDeliveryDiagnostic.outputAtObservation = outputAfterStop
        AppLogger.shared.write(
            "APPLE REMOTE AUDIO playback_stop phase=completed " +
                "result=completed completion=\(drainOutcome.rawValue) reason=\(reason) " +
                "generation=\(deliveryGeneration) " +
                "pending_before_buffers=\(appleRemoteAudioStopPendingBuffers) " +
                "pending_before_samples=\(appleRemoteAudioStopPendingSamples) " +
                "pending_after_buffers=\(outputAfterStop.pendingBuffers) " +
                "pending_after_samples=\(outputAfterStop.pendingSamples) " +
                "played_buffers=\(outputAfterStop.counters.playedBuffers) " +
                "played_samples=\(outputAfterStop.counters.playedSamples) " +
                "interrupted_buffers=\(appleRemoteAudioStopInterruptedBuffers) " +
                "interrupted_samples=\(appleRemoteAudioStopInterruptedSamples)"
        )
        AppLogger.shared.write(
            "APPLE REMOTE VOICE phase=completed result=\(released ? "stopped" : "release_failed") " +
                "reason=\(reason) audio_batches=\(appleRemoteAudioBatchCount) " +
                "audio_samples=\(appleRemoteAudioSampleCount) " +
                "enqueue_failures=\(appleRemoteAudioEnqueueFailureCount) route=BuddyMic2ch"
        )
        activeAppleRemoteVoiceOperationID = nil
        activeAppleRemoteVoiceStartedAt = nil
        if !deferredDevices.isEmpty {
            deferredDevices.forEach { beginAppleRemoteVoice(for: $0) }
        } else {
            releaseVirtualAudioOutputIfUnused(reason: "apple_remote_voice_finished")
        }
    }

    func receiveAppleRemoteAudio(_ samples: [Int16]) {
        guard (!appleRemoteVoiceDevices.isEmpty || appleRemoteVoiceStopping),
              !samples.isEmpty
        else { return }
        if !pendingAppleRemoteVoiceStarts.isEmpty,
           pendingAppleRemoteVoiceAudio.appendIfWaiting(samples) {
            AppLogger.shared.write(
                "APPLE REMOTE AUDIO buffered_during_configuration samples=\(samples.count) " +
                    "total=\(pendingAppleRemoteVoiceAudio.bufferedSampleCount)"
            )
            return
        }
        publishCurrentVoiceSampleReceiptIfNeeded(sampleCount: samples.count)
        let deliveryGeneration = voiceAudioDeliveryDiagnostic.generation
        let accepted = audioOutput.enqueue(
            samples: samples,
            deliveryGeneration: deliveryGeneration
        )
        recordVoiceAudioReceipt(samples: samples, route: .virtualAudioDirect)
        recordVoiceAudioEnqueueOutcome(
            accepted: accepted,
            deliveryGeneration: deliveryGeneration
        )
        appleRemoteAudioBatchCount += 1
        appleRemoteAudioSampleCount += samples.count
        if !accepted { appleRemoteAudioEnqueueFailureCount += 1 }
        if !loggedAppleRemoteAudioDevice {
            loggedAppleRemoteAudioDevice = true
            AppLogger.shared.write(
                "APPLE REMOTE AUDIO routed source=apple_remote_microphone " +
                    "route=virtual_audio device=BuddyMic2ch accepted=\(accepted) " +
                    "first_batch_samples=\(samples.count) " +
                    "pending_buffers=\(audioOutput.pendingVoiceBufferCountForDiagnostics)"
            )
        }
    }

    func resetAppleRemoteState(
        for device: SiriRemoteDeviceIdentity,
        reason: String
    ) {
        if appleRemoteAppSwitcherSession.isActive {
            finishAppleRemoteAppSwitcher(reason: "input_reset_\(reason)", confirmed: false)
        }
        let doubleClickKeys = appleRemoteDoubleClickTimers.keys.filter { $0.device == device }
        doubleClickKeys.forEach {
            appleRemoteDoubleClickTimers.removeValue(forKey: $0)?.cancel()
        }
        let longPressKeys = appleRemoteLongPressTimers.keys.filter { $0.device == device }
        longPressKeys.forEach {
            appleRemoteLongPressTimers.removeValue(forKey: $0)?.cancel()
        }
        let repeatKeys = appleRemoteRepeatTimers.keys.filter { $0.device == device }
        repeatKeys.forEach {
            cancelAppleRemoteRepeat(
                for: $0.button,
                device: $0.device,
                reason: reason
            )
        }
        appleRemoteGestureRecognizers.removeValue(forKey: device)
        appleRemoteActiveButtons.removeValue(forKey: device)
        appleRemoteActiveControlIDs.removeValue(forKey: device)
        appleRemoteHoverClickDevices.remove(device)
        siriRemoteCursorFeedback.cancelInteraction(reason: "device_reset")
        endAppleRemoteVoice(for: device, reason: reason)
        refreshAppleRemoteActiveButtons()
        refreshAppleRemoteActiveControlIDs()
    }

    func resetAllAppleRemoteState(reason: String) {
        let devices = Set(appleRemoteProfileIDs.keys)
            .union(appleRemoteGestureRecognizers.keys)
            .union(appleRemoteVoiceDevices)
            .union(appleRemoteRepeatTimers.keys.map(\.device))
            .union(appleRemoteDoubleClickTimers.keys.map(\.device))
            .union(appleRemoteLongPressTimers.keys.map(\.device))
        devices.forEach { resetAppleRemoteState(for: $0, reason: reason) }
        finishAppleRemoteAppSwitcher(reason: reason, confirmed: false)
        appleRemoteProfileIDs.removeAll()
        connectedAppleRemoteProfileIDs.removeAll()
        appleRemoteActiveButtons.removeAll()
        appleRemoteActiveControlIDs.removeAll()
        appleRemoteHoverClickDevices.removeAll()
        activeAppleRemoteControlIDs = []
        refreshBluetoothPresentation()
    }

    func refreshAppleRemoteActiveButtons() {
        guard let selectedProfileID = settings.selectedRemoteProfileID,
              settings.selectedRemoteProfile?.model.isAppleSiriRemote == true
        else { return }
        activeRemoteButtons = appleRemoteProfileIDs.reduce(into: Set<RemoteButton>()) {
            result, entry in
            guard entry.value == selectedProfileID else { return }
            result.formUnion(appleRemoteActiveButtons[entry.key] ?? [])
        }
    }

    func refreshAppleRemoteActiveControlIDs() {
        guard let selectedProfileID = settings.selectedRemoteProfileID,
              settings.selectedRemoteProfile?.model.isAppleSiriRemote == true
        else { return }
        activeAppleRemoteControlIDs = appleRemoteProfileIDs.reduce(into: Set<String>()) {
            result, entry in
            guard entry.value == selectedProfileID else { return }
            result.formUnion(appleRemoteActiveControlIDs[entry.key] ?? [])
        }
    }

    func refreshAppleRemoteHIDStatus() {
        guard settings.selectedRemoteProfile?.model.isAppleSiriRemote == true else { return }
        if !settings.customMappingEnabled {
            hidStatus = LocalizedMessage("button_mapping.status.system_managed")
        } else if !HIDRemoteMonitor.isInputMonitoringGranted {
            hidStatus = LocalizedMessage("button_mapping.permission.input_monitoring_required")
        } else if !KeyboardInjector.isAccessibilityTrusted {
            hidStatus = LocalizedMessage("button_mapping.permission.accessibility_required")
        } else if let profileID = settings.selectedRemoteProfileID,
                  connectedAppleRemoteProfileIDs.contains(profileID) {
            hidStatus = LocalizedMessage("button_mapping.status.connected")
        } else {
            hidStatus = LocalizedMessage("button_mapping.status.waiting_for_device")
        }
    }

    func beginAppleRemoteVoice(for device: SiriRemoteDeviceIdentity) {
        guard canAcceptNewVoiceSession(from: .appleRemote),
              appleRemoteVoiceDevices.isEmpty || appleRemoteVoiceDevices.contains(device),
              pendingVoiceKeyActivationOwner == nil else {
            AppLogger.shared.write("APPLE REMOTE VOICE phase=pending result=source_activation_busy")
            return
        }
        let outputReadyAtStart = audioOutput.isReadyForTestTone
        var shouldStartConfiguration = false
        if !outputReadyAtStart {
            shouldStartConfiguration = pendingAppleRemoteVoiceStarts.isEmpty
            pendingAppleRemoteVoiceStarts.insert(device)
            if shouldStartConfiguration {
                pendingAppleRemoteVoiceAudio.begin()
            }
        }
        if appleRemoteAppSwitcherSession.isActive {
            finishAppleRemoteAppSwitcher(reason: "voice_started", confirmed: false)
        }
        pendingAppleRemoteVoiceStops.cancel(device)
        guard appleRemoteVoiceDevices.insert(device).inserted else { return }
        appleRemoteVoiceCaptureRetryWorkItem?.cancel()
        appleRemoteVoiceCaptureRetryWorkItem = nil
        appleRemoteVoiceCaptureRetryAttempt = 0
        siriRemoteCursorFeedback.cancelInteraction(reason: "voice_started")
        siriRemoteFeature.setVoiceTouchSuppressed(true)
        if appleRemoteVoiceStopping {
            if siriRemoteFeature.resumeCaptureIfStopping() {
                appleRemoteVoiceStopOperation &+= 1
                appleRemoteVoiceStopping = false
                audioOutput.cancelPendingDrain()
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=resumed result=continued_session " +
                        "reason=rapid_repress stage=capture_closing"
                )
                return
            }
            if siriRemoteFeature.beginCapture() {
                appleRemoteVoiceStopOperation &+= 1
                appleRemoteVoiceStopping = false
                audioOutput.cancelPendingDrain()
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=resumed result=continued_session " +
                        "reason=rapid_repress stage=playback_draining"
                )
                return
            }
            AppLogger.shared.write(
                "APPLE REMOTE VOICE phase=deferred reason=previous_session_draining"
            )
            return
        }
        guard appleRemoteVoiceDevices.count == 1 else {
            AppLogger.shared.write(
                "APPLE REMOTE VOICE phase=completed result=joined_active_session"
            )
            return
        }
        appleRemoteVoiceOperationCounter &+= 1
        let operationID = "apple_remote_voice_\(appleRemoteVoiceOperationCounter)"
        appleRemoteAudioBatchCount = 0
        appleRemoteAudioSampleCount = 0
        appleRemoteAudioEnqueueFailureCount = 0
        appleRemoteAudioStopPendingBuffers = 0
        appleRemoteAudioStopPendingSamples = 0
        appleRemoteAudioStopInterruptedBuffers = 0
        appleRemoteAudioStopInterruptedSamples = 0
        loggedAppleRemoteAudioDevice = false
        if outputReadyAtStart {
            guard ensureVirtualAudioOutputReady(reason: "apple_remote_voice_start") else {
                appleRemoteVoiceDevices.remove(device)
                siriRemoteFeature.setVoiceTouchSuppressed(false)
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=failed result=audio_output_unavailable route=BuddyMic2ch"
                )

                return
            }
        }
        updateVoiceKeyState(
            streaming: true,
            forceSoftware: true,
            owner: .appleRemote
        ) { [self] activated in
            guard activated else {
                appleRemoteVoiceDevices.remove(device)
                if shouldStartConfiguration {
                    pendingAppleRemoteVoiceStarts.remove(device)
                    pendingAppleRemoteVoiceAudio.cancel()
                    pendingAppleRemoteVoiceStops.cancel(device)
                }
                siriRemoteFeature.setVoiceTouchSuppressed(false)
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=failed result=voice_key_press_failed"
                )

                return
            }
            beginVoiceSessionIfNeeded()
            activeAppleRemoteVoiceOperationID = operationID
            activeAppleRemoteVoiceStartedAt = Date()
            guard siriRemoteFeature.beginCapture() else {
                if shouldStartConfiguration {
                    pendingAppleRemoteVoiceStarts.remove(device)
                    pendingAppleRemoteVoiceAudio.cancel()
                    pendingAppleRemoteVoiceStops.cancel(device)
                }
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=pending result=audio_capture_not_ready " +
                        "retry_attempt=\(appleRemoteVoiceCaptureRetryAttempt)"
                )
                scheduleAppleRemoteVoiceCaptureRetry(for: device)
                AppLogger.shared.write(
                    "APPLE REMOTE VOICE phase=held result=input_method_wake_preserved"
                )
                return
            }
            AppLogger.shared.write(
                "APPLE REMOTE VOICE phase=started result=triggered audio_capture=requested " +
                    "audio_source=apple_remote_microphone route=BuddyMic2ch"
            )

            if !outputReadyAtStart, shouldStartConfiguration {
                AppLogger.shared.write(
                    "SYSTEM AUDIO voice_start_recovery configured=pending " +
                        "suspended=\(systemAudioSuspensionState.isSuspended) " +
                        "reasons=\(systemAudioSuspensionState.diagnostic)"
                )
                ensureVirtualAudioOutputReady(reason: "apple_remote_voice_start") { [weak self] ready in
                    guard let self else { return }
                    let pendingDevices = self.pendingAppleRemoteVoiceStarts
                    self.pendingAppleRemoteVoiceStarts.removeAll()
                    let stoppedDevices = self.pendingAppleRemoteVoiceStops.take(pending: pendingDevices)
                    let bufferedAudio = self.pendingAppleRemoteVoiceAudio.drain()
                    guard ready else {
                        self.pendingAppleRemoteVoiceAudio.cancel()
                        for pendingDevice in pendingDevices {
                            self.endAppleRemoteVoice(
                                for: pendingDevice,
                                reason: "audio_output_unavailable"
                            )
                        }
                        return
                    }
                    if !bufferedAudio.isEmpty {
                        AppLogger.shared.write(
                            "APPLE REMOTE AUDIO flush_after_configuration samples=\(bufferedAudio.count)"
                        )
                        self.receiveAppleRemoteAudio(bufferedAudio)
                    }
                    for pendingDevice in stoppedDevices {
                        self.endAppleRemoteVoice(for: pendingDevice, reason: "released_before_audio_ready")
                    }
                }
            }
        }
    }
}

/// A release queued during shared audio setup belongs to that device alone.
struct DeviceVoiceStopRequests<Device: Hashable> {
    private var devices = Set<Device>()
    mutating func request(_ device: Device) { devices.insert(device) }
    mutating func cancel(_ device: Device) { devices.remove(device) }
    mutating func removeAll() { devices.removeAll() }
    mutating func take(pending: Set<Device>) -> Set<Device> {
        let stopped = devices.intersection(pending)
        devices.subtract(pending)
        return stopped
    }
}

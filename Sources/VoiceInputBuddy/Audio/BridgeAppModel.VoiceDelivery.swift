import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    /// Includes pending activation and draining tails, before their async callbacks
    /// publish isStreaming. Transport-specific identity checks remain at each entry.
    func canAcceptNewVoiceSession(from owner: VoiceFunctionKeyLatch.Owner) -> Bool {
        guard !systemAudioSuspensionState.isSuspended,
              voiceKeyReleaseRetry == nil else { return false }
        if let pending = pendingVoiceKeyActivationOwner, pending != owner { return false }
        if owner != .bluetooth,
           bluetoothVoiceActive || pendingBluetoothVoiceStart.identifier != nil ||
            voiceFnTapSession.requiresCleanupBeforeMapping { return false }
        if owner != .appleRemote,
           !appleRemoteVoiceDevices.isEmpty || !pendingAppleRemoteVoiceStarts.isEmpty ||
            appleRemoteVoiceStopping { return false }
        if owner != .mobile,
           activeMobileVoiceSource != nil || stoppingMobileVoiceSource != nil ||
            pendingMobileVoiceStartSource != nil || pendingMobileVoiceActivationSource != nil { return false }
        return true
    }

    func resetCurrentVoiceSampleReceipt() {
        guard hasReceivedCurrentVoiceSamples else { return }
        hasReceivedCurrentVoiceSamples = false
    }

    func publishCurrentVoiceSampleReceiptIfNeeded(sampleCount: Int) {
        guard VoiceSamplePresentationPolicy.shouldPublishReceipt(
            hasReceivedSamples: hasReceivedCurrentVoiceSamples,
            sampleCount: sampleCount
        ) else { return }
        hasReceivedCurrentVoiceSamples = true
    }

    func voiceAudioDeliveryDiagnosticSnapshot() -> VoiceAudioDeliveryDiagnostic {
        var diagnostic = voiceAudioDeliveryDiagnostic
        diagnostic.outputAtObservation = audioOutput.diagnosticSnapshot(
            deliveryGeneration: diagnostic.generation
        )
        return diagnostic
    }

    func recordVoiceAudioReceipt(
        samples: [Int16],
        route: VoiceAudioDeliveryRoute
    ) {
        guard !samples.isEmpty, voiceAudioDeliveryDiagnostic.generation > 0 else { return }
        voiceAudioDeliveryDiagnostic.route = route
        voiceAudioDeliveryDiagnostic.receivedBatches += 1
        voiceAudioDeliveryDiagnostic.receivedSamples += samples.count
        voiceAudioDeliveryDiagnostic.outputAtObservation = audioOutput.diagnosticSnapshot(
            deliveryGeneration: voiceAudioDeliveryDiagnostic.generation
        )
    }

    func recordVoiceAudioEnqueueOutcome(
        accepted: Bool,
        deliveryGeneration: Int
    ) {
        guard !accepted,
              deliveryGeneration > 0,
              voiceAudioDeliveryDiagnostic.generation == deliveryGeneration
        else { return }
        voiceAudioDeliveryDiagnostic.enqueueFailures += 1
        voiceAudioDeliveryDiagnostic.outputAtObservation = audioOutput.diagnosticSnapshot(
            deliveryGeneration: deliveryGeneration
        )
    }

    func enqueueVoiceFnTapAudio(_ samples: [Int16], isPreRoll: Bool = false) {
        let deliveryGeneration = voiceAudioDeliveryDiagnostic.generation
        let accepted = audioOutput.enqueue(
            samples: samples,
            deliveryGeneration: deliveryGeneration,
            isPreRoll: isPreRoll
        )
        recordVoiceAudioEnqueueOutcome(
            accepted: accepted,
            deliveryGeneration: deliveryGeneration
        )
        if !accepted {
            bluetoothVoiceEnqueueFailureCount += 1
        }
    }

    func beginVoiceSessionIfNeeded() {
        guard !isStreaming else { return }

        cancelTestToneIfNeeded(
            statusMessage: LocalizedMessage("audio.test_tone.blocked_voice_active"),
            logReason: "voice_start"
        )
        let source = currentVoiceSource
        let sessionID = UUID()
        voiceAudioDeliveryGeneration &+= 1
        let audioSnapshot = audioOutput.diagnosticSnapshot(
            deliveryGeneration: voiceAudioDeliveryGeneration
        )
        voiceAudioDeliveryDiagnostic = VoiceAudioDeliveryDiagnostic(
            generation: voiceAudioDeliveryGeneration,
            source: source.rawValue,
            outputAtStart: audioSnapshot,
            outputAtObservation: audioSnapshot,
            countersAtStart: audioSnapshot.counters
        )
        activeVoiceSource = source
        voiceSessionID = sessionID
        isStreaming = true
    }

    func endVoiceSessionIfNeeded(flushAudio: Bool = true, applyPendingMappings: (() -> Void)? = nil) {
        defer { flushPendingVoiceToolMappingRefresh(applyMappings: applyPendingMappings) }
        guard !bluetoothVoiceActive,
              appleRemoteVoiceDevices.isEmpty,
              !appleRemoteVoiceStopping,
              activeMobileVoiceSource == nil,
              isStreaming
        else { return }
        voiceSessionID = nil
        voiceAudioDeliveryDiagnostic.sessionEnded = true
        voiceAudioDeliveryDiagnostic.outputAtObservation = audioOutput.diagnosticSnapshot(
            deliveryGeneration: voiceAudioDeliveryDiagnostic.generation
        )
        isStreaming = false
        activeVoiceSource = nil
        if flushAudio {
            audioOutput.endSession()
        }

    }

    private var currentVoiceSource: RemoteInputSource {
        if bluetoothVoiceActive || !appleRemoteVoiceDevices.isEmpty || appleRemoteVoiceStopping {
            return .bluetoothRemote
        }
        switch activeMobileVoiceSource {
        case .nearbyPhone, .nearbyWatch: return .nearbyPhone
        case .web: return .webRemote
        case nil: return .unknown
        }
    }

    @discardableResult
    func applyVoiceFunctionMapping(neutralizeVoiceKey: Bool) -> Bool {
        voiceFunctionMapper.additionalIdentities = Set(settings.compatibleHIDIdentities(
            includeXiaomi: true, includeGoogle: false))
        let applied = voiceFunctionMapper.apply(
            suppressPowerKey: settings.customMappingEnabled,
            neutralizeVoiceKey: neutralizeVoiceKey
        )
        if !isStreaming {
            isVoiceTriggerEnabled = applied
            voiceShortcutStatus = LocalizedMessage(
                applied
                    ? "voice_button.status.\(settings.voiceKeyMode.rawValue)_enabled"
                    : "voice_button.status.waiting"
            )
        }
        return !settings.customMappingEnabled || voiceFunctionMapper.isPowerKeySuppressed
    }

    @discardableResult
    // Main-queue state transitions; source activation completes without a nested run loop.
    func updateVoiceKeyState(
        streaming: Bool,
        forceSoftware: Bool,
        owner: VoiceFunctionKeyLatch.Owner,
        keySetter: @escaping (VoiceKeyMode, Bool) -> Bool = { KeyboardInjector.setVoiceKeyPressed($0, isPressed: $1) },
        completion: @escaping (Bool) -> Void = { _ in }
    ) -> Bool {
        guard !streaming || (!systemAudioSuspensionState.isSuspended && voiceKeyReleaseRetry == nil) else {
            completion(false)
            return false
        }
        let mode = streaming
            ? settings.voiceKeyMode
            : (heldVoiceKeyMode ?? pendingVoiceKeyMode ?? settings.voiceKeyMode)
        guard forceSoftware || !mode.usesHardwareMapping else { completion(true); return true }
        if VoiceKeyPendingDownPolicy.shouldRejectStart(
            streaming: streaming,
            pendingDown: pendingVoiceKeyMode != nil || voiceKeyActivationInProgress
        ) {
            AppLogger.shared.write(
                "VOICE KEY start_rejected reason=pending_down owner=\(owner)"
            )
            completion(false)
            return false
        }
        guard let transition = voiceKeyLatch.transition(
            streaming: streaming,
            owner: owner
        ) else {
            completion(true)
            return true
        }
        let shouldHold = transition == .press
        if shouldHold {
            pendingVoiceKeyMode = mode
            voiceKeyActivationInProgress = true
            voiceKeyActivationGeneration &+= 1
            let generation = voiceKeyActivationGeneration
            pendingVoiceKeyActivationOwner = owner
            pendingVoiceKeyActivationCompletion = completion
            if owner == .bluetooth { pendingCommandVoiceAudio.begin() }
            var immediateResult: Bool?
            preferredInputSourceMonitor.beginVoiceSession { [weak self] activated in
                guard let self else { completion(false); return }
                guard self.voiceKeyActivationGeneration == generation,
                      self.pendingVoiceKeyActivationOwner == owner else { immediateResult = false; return }
                self.voiceKeyActivationInProgress = false
                self.pendingVoiceKeyActivationOwner = nil
                let finish = self.pendingVoiceKeyActivationCompletion
                self.pendingVoiceKeyActivationCompletion = nil
                defer { self.flushPendingVoiceToolMappingRefresh() }
                guard activated, !self.systemAudioSuspensionState.isSuspended, self.pendingVoiceKeyMode == mode else {
                    self.pendingVoiceKeyMode = nil
                    if owner == .bluetooth { self.pendingCommandVoiceAudio.cancel() }
                    self.voiceKeyLatch.rollback(transition, owner: owner)
                    immediateResult = false
                    finish?(false)
                    return
                }
                let submitted = self.submitVoiceKeyState(mode: mode, shouldHold: true,
                    transition: transition, owner: owner, keySetter: keySetter)
                immediateResult = submitted
                finish?(submitted)
            }
            // An asynchronous start is accepted; the caller continues only at completion.
            return immediateResult ?? true
        }
        defer { flushPendingVoiceToolMappingRefresh() }
        if !shouldHold,
           heldVoiceKeyMode == nil, pendingVoiceKeyMode != nil {
            pendingVoiceKeyMode = nil
            if owner == .bluetooth {
                pendingCommandVoiceAudio.cancel()
            }
            cancelPendingVoiceKeyActivation()
            isVoiceTriggerEnabled = true
            AppLogger.shared.write(
                "VOICE KEY mode=\(mode.rawValue) pending_down_cancelled"
            )
            completion(true)
            return true
        }
        let submitted = submitVoiceKeyState(mode: mode, shouldHold: shouldHold,
            transition: transition, owner: owner, keySetter: keySetter)
        completion(submitted)
        return submitted
    }

    private func cancelPendingVoiceKeyActivation() {
        voiceKeyActivationGeneration &+= 1
        voiceKeyActivationInProgress = false
        pendingVoiceKeyActivationOwner = nil
        let completion = pendingVoiceKeyActivationCompletion
        pendingVoiceKeyActivationCompletion = nil
        preferredInputSourceMonitor.endVoiceSession()
        completion?(false)
    }

    private func submitVoiceKeyState(
        mode: VoiceKeyMode, shouldHold: Bool,
        transition: VoiceFunctionKeyTransition, owner: VoiceFunctionKeyLatch.Owner,
        keySetter: (VoiceKeyMode, Bool) -> Bool
    ) -> Bool {
        guard keySetter(mode, shouldHold) else {
            if shouldHold {
                pendingVoiceKeyMode = nil
                if owner == .bluetooth {
                    pendingCommandVoiceAudio.cancel()
                }
                preferredInputSourceMonitor.endVoiceSession()
            }
            voiceKeyLatch.rollback(transition, owner: owner)
            AppLogger.shared.write(
                "VOICE KEY \(mode.rawValue) \(shouldHold ? "DOWN" : "UP") failed"
            )
            return false
        }
        if shouldHold {
            preferredInputSourceMonitor.markVoiceTriggerSubmitted()
        } else {
            preferredInputSourceMonitor.endVoiceSession()
        }
        if shouldHold {
            voiceKeyReleaseRetry?.cancel()
            voiceKeyReleaseRetry = nil
            voiceKeyReleaseRetryGeneration &+= 1
            pendingVoiceKeyMode = nil
            heldVoiceKeyMode = mode
        } else {
            heldVoiceKeyMode = nil
        }
        isVoiceTriggerEnabled = !shouldHold
        voiceShortcutStatus = LocalizedMessage(
            shouldHold
                ? "voice_button.status.\(mode.rawValue)_pressed"
                : "voice_button.status.\(mode.rawValue)_released"
        )
        AppLogger.shared.write(
            "VOICE KEY mode=\(mode.rawValue) edge=\(shouldHold ? "down" : "up") " +
                "result=event_submitted target_response=unknown"
        )
        return true
    }

    @discardableResult
    func releaseVoiceKeyIfNeeded(
        owner: VoiceFunctionKeyLatch.Owner,
        forceSoftware: Bool
    ) -> Bool {
        guard !updateVoiceKeyState(
            streaming: false,
            forceSoftware: forceSoftware,
            owner: owner
        ) else { return true }
        return releaseVoiceKeyIfNeeded()
    }

    @discardableResult
    func releaseVoiceKeyIfNeeded(
        releaseKey: @escaping (VoiceKeyMode) -> Bool = {
            KeyboardInjector.setVoiceKeyPressed($0, isPressed: false)
        }
    ) -> Bool {
        defer { flushPendingVoiceToolMappingRefresh() }
        voiceKeyReleaseRetry?.cancel()
        voiceKeyReleaseRetry = nil
        voiceKeyReleaseRetryGeneration &+= 1
        let generation = voiceKeyReleaseRetryGeneration
        guard voiceKeyLatch.isHeld else {
            heldVoiceKeyMode = nil
            pendingVoiceKeyMode = nil
            pendingCommandVoiceAudio.cancel()
            if pendingVoiceKeyActivationCompletion != nil { cancelPendingVoiceKeyActivation() }
            return true
        }
        guard let heldVoiceKeyMode else {
            guard pendingVoiceKeyMode != nil else { return false }
            voiceKeyLatch.reset()
            pendingVoiceKeyMode = nil
            pendingCommandVoiceAudio.cancel()
            cancelPendingVoiceKeyActivation()
            isVoiceTriggerEnabled = true
            AppLogger.shared.write("VOICE KEY pending_down_cancelled reason=forced_release")
            return true
        }

        // A denied post must not erase the held-key safety state. Retry after permission recovery.
        guard releaseKey(heldVoiceKeyMode) else {
            AppLogger.shared.write("VOICE KEY cleanup deferred reason=release_failed mode=\(heldVoiceKeyMode.rawValue)")
            voiceKeyReleaseRetry = scheduleVoiceKeyReleaseRetry(1) { [weak self] in
                guard let self, self.voiceKeyReleaseRetryGeneration == generation,
                      self.heldVoiceKeyMode == heldVoiceKeyMode else { return }
                _ = self.releaseVoiceKeyIfNeeded(releaseKey: releaseKey)
            }
            return false
        }

        voiceKeyLatch.reset()
        self.heldVoiceKeyMode = nil
        preferredInputSourceMonitor.endVoiceSession()
        isVoiceTriggerEnabled = true
        voiceShortcutStatus = LocalizedMessage(
            "voice_button.status.\(heldVoiceKeyMode.rawValue)_released"
        )
        AppLogger.shared.write(
            "VOICE KEY mode=\(heldVoiceKeyMode.rawValue) edge=up " +
                "result=event_submitted target_response=unknown"
        )
        return true
    }

    /// 苹果遥控器自报能力的日志标记（真机核对用）。
    private static func describeSiri(_ declared: SiriRemoteDeclaredCapabilities) -> String {
        var names: [String] = []
        if declared.contains(.controlEdges) { names.append("control_edges") }
        if declared.contains(.touchSurface) { names.append("touch_surface") }
        if declared.contains(.continuousScroll) { names.append("continuous_scroll") }
        if declared.contains(.voiceStream) { names.append("voice_stream") }
        if declared.contains(.batteryLevel) { names.append("battery_level") }
        if declared.contains(.powerState) { names.append("power_state") }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }
}

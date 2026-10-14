import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
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

    func enqueueVoiceFnTapAudio(_ samples: [Int16]) {
        let deliveryGeneration = voiceAudioDeliveryDiagnostic.generation
        let accepted = audioOutput.enqueue(
            samples: samples,
            deliveryGeneration: deliveryGeneration
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
        privateFeature.startVoiceSession()
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

    func endVoiceSessionIfNeeded(flushAudio: Bool = true) {
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
        privateFeature.finishVoiceSession()
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
    func updateVoiceKeyState(
        streaming: Bool,
        forceSoftware: Bool,
        owner: VoiceFunctionKeyLatch.Owner
    ) -> Bool {
        let mode = streaming
            ? settings.voiceKeyMode
            : (heldVoiceKeyMode ?? pendingVoiceKeyMode ?? settings.voiceKeyMode)
        guard forceSoftware || !mode.usesHardwareMapping else { return true }
        if VoiceKeyPendingDownPolicy.shouldRejectStart(
            streaming: streaming,
            pendingDown: pendingVoiceKeyMode != nil
        ) {
            AppLogger.shared.write(
                "VOICE KEY start_rejected reason=pending_down owner=\(owner)"
            )
            return false
        }
        guard let transition = voiceKeyLatch.transition(
            streaming: streaming,
            owner: owner
        ) else {
            return true
        }
        let shouldHold = transition == .press
        if shouldHold, mode != .function {
            pendingVoiceKeyMode = mode
            if owner == .bluetooth {
                pendingCommandVoiceAudio.begin()
            }
            if !preferredInputSourceMonitor.beginVoiceSession() {
                pendingVoiceKeyMode = nil
                if owner == .bluetooth {
                    pendingCommandVoiceAudio.cancel()
                }
                voiceKeyLatch.rollback(transition, owner: owner)
                AppLogger.shared.write(
                    "VOICE INPUT source_prepare_failed mode=\(mode.rawValue)"
                )
                return false
            }
        }
        if !shouldHold, mode != .function,
           heldVoiceKeyMode == nil, pendingVoiceKeyMode != nil {
            pendingVoiceKeyMode = nil
            if owner == .bluetooth {
                pendingCommandVoiceAudio.cancel()
            }
            preferredInputSourceMonitor.endVoiceSession()
            isVoiceTriggerEnabled = true
            AppLogger.shared.write(
                "VOICE KEY mode=\(mode.rawValue) pending_down_cancelled"
            )
            return true
        }
        guard KeyboardInjector.setVoiceKeyPressed(mode, isPressed: shouldHold) else {
            if shouldHold, mode != .function {
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
        if mode != .function, !shouldHold {
            preferredInputSourceMonitor.endVoiceSession()
        }
        if shouldHold {
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
        releaseKey: (VoiceKeyMode) -> Bool = {
            KeyboardInjector.setVoiceKeyPressed($0, isPressed: false)
        }
    ) -> Bool {
        guard voiceKeyLatch.isHeld else {
            heldVoiceKeyMode = nil
            pendingVoiceKeyMode = nil
            pendingCommandVoiceAudio.cancel()
            return true
        }
        guard let heldVoiceKeyMode else {
            guard pendingVoiceKeyMode != nil else { return false }
            voiceKeyLatch.reset()
            pendingVoiceKeyMode = nil
            pendingCommandVoiceAudio.cancel()
            preferredInputSourceMonitor.endVoiceSession()
            isVoiceTriggerEnabled = true
            AppLogger.shared.write("VOICE KEY pending_down_cancelled reason=forced_release")
            return true
        }

        // A denied post must not erase the held-key safety state. Retry after permission recovery.
        guard releaseKey(heldVoiceKeyMode) else {
            AppLogger.shared.write("VOICE KEY cleanup deferred reason=release_failed mode=\(heldVoiceKeyMode.rawValue)")
            return false
        }

        voiceKeyLatch.reset()
        self.heldVoiceKeyMode = nil
        if heldVoiceKeyMode != .function {
            preferredInputSourceMonitor.endVoiceSession()
        }
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

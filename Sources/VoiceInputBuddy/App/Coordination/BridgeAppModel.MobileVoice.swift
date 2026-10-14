import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    private func startPhoneVoice(source: MobileVoiceSource, completion: @escaping (RemoteVoiceStartResult) -> Void) {
        mobileVoiceOperationCounter &+= 1
        let operationID = "mobile_voice_\(mobileVoiceOperationCounter)"
        guard activeMobileVoiceSource == nil, pendingMobileVoiceActivationSource == nil else {
            AppLogger.shared.write(
                "MOBILE VOICE start_rejected reason=busy requested=\(source.logName) " +
                    "active=\(activeMobileVoiceSource?.logName ?? "none")"
            )

            completion(.busy)
            return
        }
        cancelVirtualAudioReleaseIfPending(trigger: "mobile_voice_start_\(source.logName)")
        pendingMobileVoiceActivationSource = source
        updateVoiceKeyState(
            streaming: true,
            forceSoftware: true,
            owner: .mobile
        ) { [self] activated in
            pendingMobileVoiceActivationSource = nil
            guard activated else {
                AppLogger.shared.write(
                    "MOBILE VOICE start_rejected reason=function_key requested=\(source.logName)"
                )

                releaseVirtualAudioOutputIfUnused(reason: "mobile_voice_function_key_failed")
                completion(.unavailable)
                return
            }
            resetCurrentVoiceSampleReceipt()
            mobileVoiceLifecycle.markStarted(source)
            mobileVoiceAudioBatchCount = 0
            mobileVoiceAudioReceivedBatchCount = 0
            mobileVoiceAudioEnqueueFailureCount = 0
            mobileVoiceAudioSourceMismatchCount = 0
            mobileVoiceAudioSignalMetrics = WatchBluetoothAudioSignalMetrics()
            beginVoiceSessionIfNeeded()
            activeMobileVoiceOperationID = operationID
            activeMobileVoiceStartedAt = Date()
            scheduleMobileVoiceNoAudioRecoveryIfNeeded(source: source)

            AppLogger.shared.write("MOBILE VOICE started source=\(source.logName)")
            completion(.started)
        }
    }

    func requestPhoneVoiceStart(
        source: MobileVoiceSource,
        completion: @escaping (RemoteVoiceStartResult) -> Void
    ) {
        guard source == .web || OnboardingBuildCapabilities.availableControlSources.contains(.appleCompanion) else {
            disablePhoneRemoteConnection()
            completion(.unavailable)
            return
        }
        guard pendingMobileVoiceActivationSource == nil else {
            completion(.busy)
            return
        }
        switch mobileVoiceLifecycle.requestStart(source) {
        case .startNow:
            startPhoneVoiceAfterAudioReady(source: source, completion: completion)
        case .deferUntilStopped:
            pendingMobileVoiceRestartCompletion = completion
            AppLogger.shared.write("MOBILE VOICE restart_deferred source=\(source.logName)")
        case .busy:
            AppLogger.shared.write(
                "MOBILE VOICE start_rejected reason=busy requested=\(source.logName) " +
                    "active=\(activeMobileVoiceSource?.logName ?? "none") " +
                    "stopping=\(stoppingMobileVoiceSource?.logName ?? "none")"
            )
            completion(.busy)
        }
    }

    private func startPhoneVoiceAfterAudioReady(
        source: MobileVoiceSource,
        completion: @escaping (RemoteVoiceStartResult) -> Void
    ) {
        let outputReadyAtStart = audioOutput.isReadyForTestTone
        if !outputReadyAtStart {
            pendingMobileVoiceStartSource = source
            pendingMobileVoiceAudio.begin()
        }
        startPhoneVoice(source: source) { [self] result in
            completion(result)
            guard result == .started, !outputReadyAtStart else {
                if result != .started {
                    pendingMobileVoiceStartSource = nil
                    pendingMobileVoiceAudio.cancel()
                    pendingMobileVoiceStopRequested = false
                }
                return
            }
            AppLogger.shared.write(
                "SYSTEM AUDIO voice_start_recovery configured=pending " +
                    "suspended=\(systemAudioSuspensionState.isSuspended) " +
                    "reasons=\(systemAudioSuspensionState.diagnostic)"
            )
            ensureVirtualAudioOutputReady(reason: "mobile_voice_start") { [weak self] ready in
                guard let self,
                      self.pendingMobileVoiceStartSource == source
                else { return }
                self.pendingMobileVoiceStartSource = nil
                let stopRequested = self.pendingMobileVoiceStopRequested
                self.pendingMobileVoiceStopRequested = false
                let bufferedAudio = self.pendingMobileVoiceAudio.drain()
                guard ready else {
                    self.pendingMobileVoiceAudio.cancel()
                    self.stopPhoneVoice(source: source)
                    return
                }
                if !bufferedAudio.isEmpty {
                    AppLogger.shared.write(
                        "MOBILE VOICE flush_after_configuration source=\(source.logName) " +
                            "samples=\(bufferedAudio.count)"
                    )
                    self.receivePhoneAudio(bufferedAudio, source: source)
                }
                if stopRequested {
                    self.stopPhoneVoice(source: source)
                }
            }
        }
    }

    func stopPhoneVoice(source: MobileVoiceSource) {
        if pendingMobileVoiceActivationSource == source {
            _ = releaseVoiceKeyIfNeeded(owner: .mobile, forceSoftware: true)
            return
        }
        if source == .nearbyWatch {
            cancelMobileVoiceNoAudioRecoveryTimer()
        }
        if pendingMobileVoiceStartSource == source {
            if activeMobileVoiceSource == source {
                pendingMobileVoiceStopRequested = true
                AppLogger.shared.write(
                    "MOBILE VOICE stop_deferred_until_audio_ready source=\(source.logName)"
                )
            } else {
                pendingMobileVoiceStartSource = nil
                pendingMobileVoiceAudio.cancel()
                pendingMobileVoiceStopRequested = false
                cancelMobileVoiceNoAudioRecoveryTimer()
                mobileVoiceAudioReceivedBatchCount = 0
                AppLogger.shared.write(
                    "MOBILE VOICE stop_ignored reason=start_pending_audio_configuration source=\(source.logName)"
                )
            }
            return
        }
        switch mobileVoiceLifecycle.beginStop(source) {
        case .ignoredInactive:
            AppLogger.shared.write(
                "MOBILE VOICE stop_ignored requested=\(source.logName) " +
                    "active=\(activeMobileVoiceSource?.logName ?? "none")"
            )

            return
        case let .ignoredAlreadyStopping(cancelledPendingRestart):
            if cancelledPendingRestart {
                let completion = pendingMobileVoiceRestartCompletion
                pendingMobileVoiceRestartCompletion = nil
                completion?(.unavailable)
                AppLogger.shared.write(
                    "MOBILE VOICE restart_cancelled source=\(source.logName) reason=stop_before_ready"
                )
            }
            AppLogger.shared.write("MOBILE VOICE stop_ignored reason=already_stopping source=\(source.logName)")
            return
        case let .begin(stopGeneration):
            logMobileVoiceAudioSummary(source: source, reason: "voice_stop")
            audioOutput.endSessionAfterDraining(
                source: source.logName,
                operationID: stopGeneration
            ) { [weak self] outcome in
                guard let self else { return }
                AppLogger.shared.write(
                    "MOBILE VOICE playback_stop phase=completed source=\(source.logName) " +
                        "completion=\(outcome.rawValue)"
                )
                switch self.mobileVoiceLifecycle.completeStop(
                    source,
                    generation: stopGeneration
                ) {
                case .ignored:
                    return
                case .stopped:
                    self.cancelMobileVoiceNoAudioRecoveryTimer()
                    self.releaseVoiceKeyIfNeeded(owner: .mobile, forceSoftware: true)
                    self.endVoiceSessionIfNeeded()
                    self.activeMobileVoiceOperationID = nil
                    self.activeMobileVoiceStartedAt = nil
                    AppLogger.shared.write("MOBILE VOICE stopped source=\(source.logName)")
                    self.releaseVirtualAudioOutputIfUnused(reason: "mobile_voice_stopped")
                case let .restart(restartSource):
                    self.cancelMobileVoiceNoAudioRecoveryTimer()
                    self.releaseVoiceKeyIfNeeded(owner: .mobile, forceSoftware: true)
                    self.endVoiceSessionIfNeeded()
                    self.activeMobileVoiceOperationID = nil
                    self.activeMobileVoiceStartedAt = nil
                    AppLogger.shared.write("MOBILE VOICE stopped source=\(source.logName)")
                    let completion = self.pendingMobileVoiceRestartCompletion
                    self.pendingMobileVoiceRestartCompletion = nil
                    self.startPhoneVoiceAfterAudioReady(source: restartSource) { result in
                        AppLogger.shared.write(
                            "MOBILE VOICE restart_completed source=\(restartSource.logName) result=\(result)"
                        )
                        completion?(result)
                    }
                }
            }
        }
    }
}

import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    var readyBluetoothBridgeCount: Int {
        bluetoothBridgeStates.values.reduce(into: 0) { count, state in
            if case .ready = state {
                count += 1
            }
        }
    }

    var shouldKeepVirtualAudioActive: Bool {
        VirtualAudioConnectionLifecyclePolicy.shouldBeActive(
            readyBluetoothBridgeCount: readyBluetoothBridgeCount,
            bluetoothVoiceActive: bluetoothVoiceActive,
            mobileVoiceActive: activeMobileVoiceSource != nil ||
                !appleRemoteVoiceDevices.isEmpty || appleRemoteVoiceStopping,
            testToneActive: isPlayingTestTone,
            systemSuspended: systemAudioSuspensionState.isSuspended
        )
    }

    var hasActiveVirtualAudioSource: Bool {
        bluetoothVoiceActive || activeMobileVoiceSource != nil ||
            !appleRemoteVoiceDevices.isEmpty || appleRemoteVoiceStopping || isPlayingTestTone
    }

    func resumeVirtualAudioOutputIfNeeded(reason: String) {
        guard shouldKeepVirtualAudioActive else {
            AppLogger.shared.write(
                "SYSTEM AUDIO resume_skipped reason=\(reason) required=false " +
                    "ready_bridges=\(readyBluetoothBridgeCount) selected=\(!settings.selectedAudioDeviceUID.isEmpty)"
            )
            return
        }
        cancelVirtualAudioReleaseIfPending(trigger: "resume_\(reason)")
        guard !settings.selectedAudioDeviceUID.isEmpty else {
            AppLogger.shared.write("SYSTEM AUDIO resume_skipped reason=\(reason) selected=false")
            return
        }
        isAudioOutputReady = audioOutput.isReadyForTestTone
        guard !isAudioOutputReady else {
            AppLogger.shared.write(
                "SYSTEM AUDIO resume_skipped reason=\(reason) already_ready=true " +
                    "state={\(audioOutput.diagnosticState())}"
            )
            return
        }
        configureVirtualAudioOutput(reason: reason) { [weak self] configured in
            guard let self else { return }
            AppLogger.shared.write(
                "SYSTEM AUDIO resume_completed reason=\(reason) configured=\(configured) " +
                    "selected_available=\(self.selectedAudioDeviceIsAvailable) " +
                    "state={\(self.audioOutput.diagnosticState())}"
            )
        }
    }

    var selectedAudioDeviceIsAvailable: Bool {
        let selectedUID = settings.selectedAudioDeviceUID
        return !selectedUID.isEmpty && audioDevices.contains { $0.uid == selectedUID }
    }

    func releaseVirtualAudioOutputIfUnused(reason: String) {
        guard !shouldKeepVirtualAudioActive else {
            AppLogger.shared.write(
                "AUDIO RELEASE skipped reason=\(reason) still_required=true " +
                    "system_suspended=\(systemAudioSuspensionState.isSuspended) " +
                    "bluetooth_voice=\(bluetoothVoiceActive) " +
                    "mobile_voice=\(activeMobileVoiceSource != nil) test_tone=\(isPlayingTestTone)"
            )
            return
        }
        guard pendingVirtualAudioRelease == nil else { return }
        let pendingVoiceBufferCount = audioOutput.pendingVoiceBufferCountForDiagnostics
        guard VirtualAudioConnectionLifecyclePolicy.shouldScheduleRelease(
            hasPendingRelease: pendingVirtualAudioRelease != nil,
            hasAllocatedOutputResources: audioOutput.hasAllocatedOutputResources,
            pendingVoiceBufferCount: pendingVoiceBufferCount
        ) else {
            isAudioOutputReady = false
            testToneStatus = LocalizedMessage("audio.output.none_or_unavailable")
            return
        }
        virtualAudioReleaseGeneration &+= 1
        let generation = virtualAudioReleaseGeneration
        pendingVirtualAudioRelease = (generation, reason)
        AppLogger.shared.write(
            "AUDIO RELEASE requested reason=\(reason) generation=\(generation) " +
                "system_suspended=\(systemAudioSuspensionState.isSuspended) " +
                "pending_buffers=\(pendingVoiceBufferCount) " +
                "state={\(audioOutput.diagnosticState())}"
        )
        audioOutput.endSessionAfterDraining(
            source: "audio_release",
            operationID: generation
        ) { [weak self] outcome in
            guard let self else { return }
            guard self.virtualAudioReleaseGeneration == generation else {
                return
            }
            self.pendingVirtualAudioRelease = nil
            guard !self.shouldKeepVirtualAudioActive else {
                AppLogger.shared.write(
                    "AUDIO RELEASE cancelled reason=\(reason) generation=\(generation) " +
                        "cause=required_again system_suspended=\(self.systemAudioSuspensionState.isSuspended) " +
                        "bluetooth_voice=\(self.bluetoothVoiceActive) " +
                        "mobile_voice=\(self.activeMobileVoiceSource != nil) " +
                        "test_tone=\(self.isPlayingTestTone)"
                )
                return
            }
            self.audioOutput.stop()
            self.isAudioOutputReady = false
            self.testToneStatus = LocalizedMessage("audio.output.none_or_unavailable")
            AppLogger.shared.write(
                "AUDIO RELEASE completed reason=\(reason) completion=\(outcome.rawValue) generation=\(generation) " +
                    "system_suspended=\(self.systemAudioSuspensionState.isSuspended) " +
                    "ready_bridges=\(self.readyBluetoothBridgeCount) " +
                    "state={\(self.audioOutput.diagnosticState())}"
            )
        }
    }

    func cancelVirtualAudioReleaseIfPending(
        trigger: String,
        cause: String = "required_again"
    ) {
        guard let pendingVirtualAudioRelease else { return }
        virtualAudioReleaseGeneration &+= 1
        self.pendingVirtualAudioRelease = nil
        audioOutput.cancelPendingDrain()
        AppLogger.shared.write(
            "AUDIO RELEASE cancelled reason=\(pendingVirtualAudioRelease.reason) " +
                "generation=\(pendingVirtualAudioRelease.generation) " +
                "current_generation=\(virtualAudioReleaseGeneration) cause=\(cause) " +
                "trigger=\(trigger) system_suspended=\(systemAudioSuspensionState.isSuspended) " +
                "ready_bridges=\(readyBluetoothBridgeCount) " +
                "bluetooth_voice=\(bluetoothVoiceActive) " +
                "mobile_voice=\(activeMobileVoiceSource != nil) test_tone=\(isPlayingTestTone)"
        )
    }

    func receivePhoneAudio(_ samples: [Int16], source: MobileVoiceSource) {
        guard source == .web || membershipFeature.canStartCompanionConnection else {
            disablePhoneRemoteConnection()
            return
        }
        guard activeMobileVoiceSource == source else {
            mobileVoiceAudioSourceMismatchCount += 1
            if mobileVoiceAudioSourceMismatchCount == 1 ||
                mobileVoiceAudioSourceMismatchCount.isMultiple(of: 20) {
                AppLogger.shared.write(
                    "MOBILE VOICE audio_dropped reason=source_mismatch requested=\(source.logName) " +
                        "active=\(activeMobileVoiceSource?.logName ?? "none") " +
                        "count=\(mobileVoiceAudioSourceMismatchCount)"
                )
            }
            return
        }
        mobileVoiceAudioReceivedBatchCount += 1
        if pendingMobileVoiceStartSource == source,
           pendingMobileVoiceAudio.appendIfWaiting(samples) {
            AppLogger.shared.write(
                "MOBILE VOICE audio buffered_during_configuration source=\(source.logName) " +
                    "samples=\(samples.count) total=\(pendingMobileVoiceAudio.bufferedSampleCount)"
            )
            return
        }
        publishCurrentVoiceSampleReceiptIfNeeded(sampleCount: samples.count)
        mobileVoiceAudioBatchCount += 1
        mobileVoiceAudioSignalMetrics.append(samples)
        let deliveryGeneration = voiceAudioDeliveryDiagnostic.generation
        let accepted = audioOutput.enqueue(
            samples: samples,
            deliveryGeneration: deliveryGeneration
        )
        recordVoiceAudioReceipt(
            samples: samples,
            route: .virtualAudioDirect
        )
        recordVoiceAudioEnqueueOutcome(
            accepted: accepted,
            deliveryGeneration: deliveryGeneration
        )
        if !accepted { mobileVoiceAudioEnqueueFailureCount += 1 }
        if mobileVoiceAudioBatchCount == 1 || mobileVoiceAudioBatchCount.isMultiple(of: 20) {
            AppLogger.shared.write(
                "MOBILE VOICE audio source=\(source.logName) batches=\(mobileVoiceAudioBatchCount) " +
                    "samples=\(mobileVoiceAudioSignalMetrics.sampleCount) " +
                    "nonzero=\(mobileVoiceAudioSignalMetrics.nonZeroSampleCount) " +
                    "peak=\(mobileVoiceAudioSignalMetrics.peak) rms=\(mobileVoiceAudioSignalMetrics.rms) " +
                    "accepted=\(accepted) enqueue_failures=\(mobileVoiceAudioEnqueueFailureCount) " +
                    "pending_buffers=\(audioOutput.pendingVoiceBufferCountForDiagnostics)"
            )
        }
    }

    func scheduleMobileVoiceNoAudioRecoveryIfNeeded(source: MobileVoiceSource) {
        cancelMobileVoiceNoAudioRecoveryTimer()
        guard source == .nearbyWatch else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(Int(MobileVoiceWatchRecoveryPolicy.noAudioTimeout)))
        timer.setEventHandler { [weak self] in
            guard let self,
                  let startedAt = self.activeMobileVoiceStartedAt,
                  self.activeMobileVoiceSource == .nearbyWatch,
                  MobileVoiceWatchRecoveryPolicy.shouldRecover(
                      startedAt: startedAt,
                      now: Date(),
                      receivedBatchCount: self.mobileVoiceAudioReceivedBatchCount
                  )
            else { return }
            AppLogger.shared.write(
                "MOBILE VOICE recovery reason=watch_no_audio timeout_s=" +
                    "\(Int(MobileVoiceWatchRecoveryPolicy.noAudioTimeout))"
            )
            self.stopPhoneVoice(source: .nearbyWatch)
        }
        mobileVoiceNoAudioRecoveryTimer = timer
        timer.resume()
    }

    func cancelMobileVoiceNoAudioRecoveryTimer() {
        mobileVoiceNoAudioRecoveryTimer?.cancel()
        mobileVoiceNoAudioRecoveryTimer = nil
    }

    func logMobileVoiceAudioSummary(source: MobileVoiceSource, reason: String) {
        AppLogger.shared.write(
            "MOBILE VOICE audio_summary source=\(source.logName) reason=\(reason) " +
                "batches=\(mobileVoiceAudioBatchCount) " +
                "samples=\(mobileVoiceAudioSignalMetrics.sampleCount) " +
                "nonzero=\(mobileVoiceAudioSignalMetrics.nonZeroSampleCount) " +
                "peak=\(mobileVoiceAudioSignalMetrics.peak) rms=\(mobileVoiceAudioSignalMetrics.rms) " +
                "enqueue_failures=\(mobileVoiceAudioEnqueueFailureCount) " +
                "source_mismatches=\(mobileVoiceAudioSourceMismatchCount) " +
                "pending_buffers=\(audioOutput.pendingVoiceBufferCountForDiagnostics)"
        )
    }
}

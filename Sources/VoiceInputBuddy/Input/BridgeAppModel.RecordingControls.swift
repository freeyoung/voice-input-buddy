import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation

extension BridgeAppModel {
    func toggleLongRecording() -> Bool {
        if longRecordingRequested {
            stopLongRecording(reason: "button_toggle")
            return true
        }
        guard isConnected,
              !bluetoothVoiceActive
        else {
            AppLogger.shared.write(
                "LONG RECORDING rejected connected=\(isConnected) audio_ready=\(isAudioOutputReady) " +
                    "bluetooth_voice=\(bluetoothVoiceActive)"
            )
            return false
        }
        if !audioOutput.isReadyForTestTone {
            ensureVirtualAudioOutputReady(reason: "long_recording_start") { [weak self] ready in
                guard let self else { return }
                if ready {
                    _ = self.toggleLongRecording()
                } else {
                    AppLogger.shared.write(
                        "LONG RECORDING rejected connected=true audio_ready=false " +
                            "bluetooth_voice=false"
                    )
                }
            }
            return true
        }

        longRecordingGeneration &+= 1
        let generation = longRecordingGeneration
        longRecordingRequested = true
        guard let selectedBluetoothBridge,
              selectedBluetoothBridge.requestMicrophoneOpen()
        else {
            finishLongRecording(reason: "open_rejected")
            return false
        }
        scheduleLongRecordingOpenTimeout(generation: generation)
        AppLogger.shared.write("LONG RECORDING opening generation=\(generation)")
        return true
    }

    private func scheduleLongRecordingOpenTimeout(generation: UInt64) {
        longRecordingOpenTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.longRecordingOpenTimeout)
        timer.setEventHandler { [weak self] in
            guard let self,
                  self.longRecordingRequested,
                  self.longRecordingGeneration == generation,
                  !self.bluetoothVoiceActive
            else { return }
            self.stopLongRecording(reason: "open_timeout")
        }
        longRecordingOpenTimer = timer
        timer.resume()
    }

    func stopLongRecording(reason: String) {
        guard longRecordingRequested else { return }
        longRecordingRequested = false
        longRecordingGeneration &+= 1
        cancelLongRecordingTimers()
        let closeWritten = selectedBluetoothBridge?.requestMicrophoneClose() ?? false
        if bluetoothVoiceActive {
            scheduleLongRecordingCloseTimeout(generation: longRecordingGeneration)
        }
        AppLogger.shared.write(
            "LONG RECORDING stopping reason=\(reason) close_written=\(closeWritten)"
        )
    }

    private func scheduleLongRecordingCloseTimeout(generation: UInt64) {
        longRecordingCloseTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.longRecordingCloseTimeout)
        timer.setEventHandler { [weak self] in
            guard let self,
                  self.longRecordingGeneration == generation,
                  !self.longRecordingRequested,
                  self.bluetoothVoiceActive
            else { return }
            self.longRecordingCloseTimer = nil
            AppLogger.shared.write("LONG RECORDING close_timeout reconnecting=true")
            self.selectedBluetoothBridge?.reconnectNow()
        }
        longRecordingCloseTimer = timer
        timer.resume()
    }

    func finishLongRecording(reason: String) {
        longRecordingRequested = false
        longRecordingGeneration &+= 1
        cancelLongRecordingTimers()
        AppLogger.shared.write("LONG RECORDING finished reason=\(reason)")
    }

    private func cancelLongRecordingTimers() {
        longRecordingOpenTimer?.cancel()
        longRecordingOpenTimer = nil
        longRecordingCloseTimer?.cancel()
        longRecordingCloseTimer = nil
    }

    func scheduleRC003VoiceExtensionOpenTimeout(generation: UInt64) {
        rc003VoiceExtensionOpenTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.rc003VoiceExtensionOpenTimeout)
        timer.setEventHandler { [weak self] in
            guard let self,
                  self.rc003VoiceExtensionActive,
                  self.rc003VoiceExtensionAwaitingReopen,
                  self.rc003VoiceExtensionGeneration == generation
            else { return }
            self.finishRC003VoiceExtensionTest(reason: "reopen_timeout")
        }
        rc003VoiceExtensionOpenTimer = timer
        timer.resume()
    }

    func scheduleRC003VoiceExtensionDeadline(generation: UInt64) {
        rc003VoiceExtensionDeadlineTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.rc003VoiceExtensionMaximumDuration)
        timer.setEventHandler { [weak self] in
            guard let self,
                  self.rc003VoiceExtensionActive,
                  self.rc003VoiceExtensionGeneration == generation
            else { return }
            self.finishRC003VoiceExtensionTest(reason: "safe_timeout")
        }
        rc003VoiceExtensionDeadlineTimer = timer
        timer.resume()
    }

    func startRC003VoiceExtensionTimer() {
        guard rc003VoiceExtensionTimer == nil,
              rc003VoiceExtensionActive,
              !rc003VoiceExtensionAwaitingReopen,
              rc003VoiceExtensionDidReceiveAudio,
              let bridge = rc003VoiceExtensionBridge
        else { return }
        let generation = rc003VoiceExtensionGeneration
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + Self.rc003VoiceExtensionInterval,
            repeating: Self.rc003VoiceExtensionInterval
        )
        timer.setEventHandler { [weak self, weak bridge] in
            guard let self,
                  let bridge,
                  self.rc003VoiceExtensionActive,
                  !self.rc003VoiceExtensionAwaitingReopen,
                  self.rc003VoiceExtensionGeneration == generation,
                  self.rc003VoiceExtensionDidReceiveAudio
            else { return }
            guard bridge.requestMicrophoneExtend() else {
                AppLogger.shared.write("RC003 EXTENSION MIC_EXTEND failed")
                self.finishRC003VoiceExtensionTest(reason: "extend_rejected")
                return
            }
            AppLogger.shared.write("RC003 EXTENSION MIC_EXTEND sent")
        }
        rc003VoiceExtensionTimer = timer
        timer.resume()
    }

    func finishRC003VoiceExtensionTest(reason: String) {
        guard rc003VoiceExtensionActive || rc003VoiceExtensionAwaitingReopen else { return }
        let bridge = rc003VoiceExtensionBridge
        let wasStreaming = bluetoothVoiceActive
        rc003VoiceExtensionActive = false
        rc003VoiceExtensionAwaitingReopen = false
        rc003VoiceExtensionDidReceiveAudio = false
        rc003VoiceExtensionGeneration &+= 1
        rc003VoiceExtensionTimer?.cancel()
        rc003VoiceExtensionTimer = nil
        rc003VoiceExtensionOpenTimer?.cancel()
        rc003VoiceExtensionOpenTimer = nil
        rc003VoiceExtensionDeadlineTimer?.cancel()
        rc003VoiceExtensionDeadlineTimer = nil
        rc003VoiceExtensionBridge = nil
        if wasStreaming {
            _ = bridge?.requestMicrophoneClose()
            AppLogger.shared.write("RC003 EXTENSION stopping reason=\(reason) close_requested=true")
            return
        }
        activeBluetoothVoiceDeviceIdentifier = nil
        bluetoothVoiceActive = false
        _ = voiceFnTapSession.stopVoice()
        releaseVoiceKeyIfNeeded(owner: .bluetooth, forceSoftware: false)
        endVoiceSessionIfNeeded(flushAudio: true)
        AppLogger.shared.write("RC003 EXTENSION finished reason=\(reason)")
    }
}

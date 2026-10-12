import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func setExperimentalContinuousRecordingEnabled(_ enabled: Bool) {
        if !enabled {
            stopLongRecording(reason: "feature_disabled")
        }
        settings.setExperimentalContinuousRecordingEnabled(enabled)
        applyHIDSettings()
    }

    func setVoiceFnTapModeEnabled(_ enabled: Bool) {
        guard settings.voiceKeyMode == .function else {
            settings.voiceFnTapModeEnabled = false
            return
        }
        if enabled {
            enableVoiceFnTapMode()
            return
        }
        settings.voiceFnTapModeEnabled = false
        voiceFnTapSession.setEnabled(false) { [weak self] in
            self?.applyHIDSettings(restartSiriRemote: false)
        }
    }

    func importConfiguration(from data: Data) throws {
        let changedVoiceKeyConfiguration: Bool
        do {
            changedVoiceKeyConfiguration = try Self.importConfiguration(
                from: data,
                into: settings,
                isStreaming: isStreaming,
                releaseVoiceKey: { releaseVoiceKeyIfNeeded() }
            )
        } catch AppConfigurationError.unsafeVoiceKeyChange {
            AppLogger.shared.write(
                "CONFIGURATION IMPORT rejected reason=unsafe_voice_key_change"
            )
            throw AppConfigurationError.unsafeVoiceKeyChange
        }
        if changedVoiceKeyConfiguration {
            preferredInputSourceMonitor.endVoiceSession()
        }
        applyAudioSettings(reason: "configuration_import")
        applyHIDSettings()
    }

    func setVoiceKeyMode(_ mode: VoiceKeyMode) {
        guard mode != settings.voiceKeyMode else { return }
        let previousMode = settings.voiceKeyMode.rawValue
        AppLogger.shared.write(
            "VOICE KEY mode_change requested from=\(previousMode) to=\(mode.rawValue)"
        )
        guard !isStreaming else {
            AppLogger.shared.write(
                "VOICE KEY mode_change_rejected reason=voice_active requested=\(mode.rawValue)"
            )
            return
        }

        guard releaseVoiceKeyIfNeeded() else {
            AppLogger.shared.write(
                "VOICE KEY mode_change_rejected reason=release_failed requested=\(mode.rawValue)"
            )
            return
        }
        preferredInputSourceMonitor.endVoiceSession()
        if mode != .function {
            settings.voiceFnTapModeEnabled = false
            voiceFnTapSession.setEnabled(false) { [weak self] in
                guard let self else { return }
                self.settings.voiceKeyMode = mode
                self.applyHIDSettings(restartSiriRemote: false)
                AppLogger.shared.write(
                    "VOICE KEY mode_change completed from=\(previousMode) to=\(mode.rawValue) result=applied"
                )
            }
            return
        }

        settings.voiceKeyMode = .function
        applyHIDSettings(restartSiriRemote: false)
        AppLogger.shared.write(
            "VOICE KEY mode_change completed from=\(previousMode) to=fn result=applied"
        )
    }

    private func enableVoiceFnTapMode() {
        guard KeyboardInjector.isAccessibilityTrusted else {
            settings.voiceFnTapModeEnabled = false
            requestNextHIDPermissionIfNeeded(voiceFnTapModeRequested: true)
            applyHIDSettings(restartSiriRemote: false)
            return
        }

        var powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: true)
        guard voiceFunctionMapper.isVoiceKeyNeutralized else {
            voiceFnTapSession.setEnabled(false)
            if HIDMappingRecoveryPolicy.shouldPreserveFnTapPreferenceAfterMappingFailure(
                hasMatchingServices: voiceFunctionMapper.hasMatchingServices
            ) {
                settings.voiceFnTapModeEnabled = true
                AppLogger.shared.write(
                    "VOICE FN TAP mode_pending_mapping reason=no_matching_service"
                )
                startHIDMonitors(powerKeySuppressed: powerKeySuppressed)
                scheduleHIDMappingRecoveryIfNeeded(restartSiriRemote: false)
                return
            }
            settings.voiceFnTapModeEnabled = false
            powerKeySuppressed = applyVoiceFunctionMapping(neutralizeVoiceKey: false)
            startHIDMonitors(powerKeySuppressed: powerKeySuppressed)
            return
        }
        settings.voiceFnTapModeEnabled = true
        voiceFnTapSession.setEnabled(true)
        startHIDMonitors(powerKeySuppressed: powerKeySuppressed)
    }

    func handleVoiceFnTapFailure(_ failure: VoiceFnTapFailure) {
        AppLogger.shared.write("VOICE FN TAP failed reason=\(failure.rawValue) fallback=hardware_fn")
        settings.voiceFnTapModeEnabled = false
        voiceFnTapSession.setEnabled(false)
        applyHIDSettings(restartSiriRemote: false)
    }

    func requestNextHIDPermissionIfNeeded(
        voiceFnTapModeRequested: Bool? = nil,
        voiceKeyModeRequested: VoiceKeyMode? = nil
    ) {
        let request = HIDPermissionGate.nextPermissionRequest(
            mappingEnabled: settings.customMappingEnabled,
            voiceFnTapModeEnabled: voiceFnTapModeRequested ?? settings.voiceFnTapModeEnabled,
            voiceKeyMode: voiceKeyModeRequested ?? settings.voiceKeyMode,
            inputMonitoringGranted: HIDRemoteMonitor.isInputMonitoringGranted,
            accessibilityGranted: KeyboardInjector.isAccessibilityTrusted
        )
        switch request {
        case .none:
            break
        case .inputMonitoring:
            _ = HIDRemoteMonitor.requestInputMonitoringAccess()
        case .accessibility:
            _ = KeyboardInjector.requestAccessibilityAccess()
        }
    }

    func requestInputMonitoringPermission() {
        _ = HIDRemoteMonitor.requestInputMonitoringAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }

    func requestAccessibilityPermission() {
        _ = KeyboardInjector.requestAccessibilityAccess()
        openPrivacyPane("Privacy_Accessibility")
    }
}

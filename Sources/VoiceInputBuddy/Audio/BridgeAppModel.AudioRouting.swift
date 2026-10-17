import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation

extension BridgeAppModel {
    func refreshAudioDevices() {
        audio.deviceRefreshGeneration &+= 1
        let generation = audio.deviceRefreshGeneration
        AppLogger.shared.write("AUDIO DEVICES refresh_requested id=\(generation)")
        audio.preparationQueue.async { [weak self] in
            let devices = CoreAudioDeviceCatalog.outputDevices()
            let diagnostic = Self.audioDevicesDiagnostic(devices)
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.started,
                      self.audio.deviceRefreshGeneration == generation
                else { return }
                self.publishAudioDevices(devices)
                AppLogger.shared.write("AUDIO DEVICES refreshed id=\(generation) \(diagnostic)")
            }
        }
    }

    func startAudioSubsystem() {
        audio.startupGeneration &+= 1
        let generation = audio.startupGeneration
        audio.startupPending = true
        AppLogger.shared.write("AUDIO STARTUP scheduled id=\(generation)")
        // Device enumeration is the only work on this queue. Route ownership is decided
        // on the main actor after enumeration, using the user's current selection.
        audio.preparationQueue.async { [weak self] in
            let devices = CoreAudioDeviceCatalog.outputDevices()
            let diagnostic = Self.audioDevicesDiagnostic(devices)
            AppLogger.shared.write("AUDIO DEVICES startup id=\(generation) \(diagnostic)")
            DispatchQueue.main.async { [weak self] in
                self?.prepareAudioStartup(generation: generation, devices: devices)
            }
        }
    }

    func prepareAudioStartup(generation: UInt64, devices: [AudioDeviceInfo],
        configureOutput: ((String, @escaping (Bool) -> Void) -> Void)? = nil) {
        guard started, audio.startupGeneration == generation else { return }
        audio.configurationGeneration &+= 1
        let configurationGeneration = audio.configurationGeneration
        if audio.suspensionState.reasons.contains(.systemSleeping) {
            finishAudioStartup(generation: generation, configurationGeneration: configurationGeneration,
                configured: false, devices: devices)
            return
        }
        let configure = configureOutput ?? { self.audio.output.configureAsync(deviceUID: $0, completion: $1) }
        configure(settings.selectedAudioDeviceUID) { [weak self] configured in
            DispatchQueue.main.async { [weak self] in
                self?.finishAudioStartup(generation: generation,
                    configurationGeneration: configurationGeneration, configured: configured,
                    devices: devices)
            }
        }
    }

    func finishAudioStartup(generation: UInt64, configurationGeneration: UInt64,
        configured: Bool, devices: [AudioDeviceInfo]) {
        // stop() owns teardown. An old completion must never tear down a newer route.
        guard started, audio.startupGeneration == generation else { return }
        if audio.configurationGeneration == configurationGeneration {
            audioStatus = audio.output.status
            isAudioOutputReady = audio.output.isReadyForTestTone
            testToneStatus = isAudioOutputReady
                ? LocalizedMessage("audio.test_tone.ready")
                : LocalizedMessage("audio.output.none_or_unavailable")
        }
        audio.startupPending = false
        publishAudioDevices(devices)
        startObservingAudioHardware()
        if audio.suspensionState.isSuspended {
            releaseVirtualAudioOutputIfUnused(reason: "startup_system_suspended")
        }
        startBluetoothConnections()
        AppLogger.shared.write(
            "AUDIO REBIND finished reason=startup success=\(configured) status=\(audioStatus.key) " +
                "state={\(audio.output.diagnosticState())}"
        )
    }

    private func publishAudioDevices(_ devices: [AudioDeviceInfo]) {
        audioDevices = devices
        doubaoAudioStatus = DoubaoAudioDevicePolicy.status(in: devices)
    }

    nonisolated private static func audioDevicesDiagnostic(_ devices: [AudioDeviceInfo]) -> String {
        "outputs={\(CoreAudioDeviceCatalog.outputDevicesDiagnostic(devices))} " +
            CoreAudioDeviceCatalog.routeDiagnostic()
    }

    @MainActor func openVirtualMicrophoneSetupInstructions(using localization: LocalizationStore) {
        guard let instructions = localization.localizedURL(
            forResource: "VirtualMicrophoneSetup",
            withExtension: "md"
        ) else {
            return
        }
        NSWorkspace.shared.open(instructions)
    }

    func applyAudioSettings(
        reason: String = "settings_change",
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        stopLongRecording(reason: "audio_reconfigure")
        guard shouldKeepVirtualAudioActive else {
            releaseVirtualAudioOutputIfUnused(reason: reason)
            completion(false)
            return
        }
        configureVirtualAudioOutput(reason: reason, completion: completion)
    }

    func handleSystemAudioLifecycle(_ event: SystemAudioLifecycleEvent) {
        let changed = audio.suspensionState.apply(event)
        AppLogger.shared.write(
            "SYSTEM AUDIO event=\(event.rawValue) changed=\(changed) " +
                "suspended=\(audio.suspensionState.isSuspended) " +
                "reasons=\(audio.suspensionState.diagnostic) started=\(started) " +
                "ready_bridges=\(readyBluetoothBridgeCount) " +
                "configured_bridges=\(connections.bridges.count) " +
                "discovery_bridge=\(connections.discoveryBridge != nil) " +
                "bluetooth_voice=\(voiceSession.isActive) " +
                "" +
                "test_tone=\(isPlayingTestTone) audio_ready=\(isAudioOutputReady)"
        )
        guard started, changed else { return }
        setBluetoothSystemSuspended(
            audio.suspensionState.isSuspended,
            reason: event.rawValue
        )
        if event == .sessionDidResignActive {
            commonPhrases.close(reason: "session_inactive")
            stopHIDMonitors()
            hidMonitoringInterrupted = true
        }
        if event == .systemWillSleep || event == .sessionDidResignActive {
            suspendActiveAudio(reason: event.rawValue)
            return
        }
        guard !audio.startupPending else {
            AppLogger.shared.write(
                "SYSTEM AUDIO lifecycle_deferred event=\(event.rawValue) cause=audio_startup_pending " +
                    "suspended=\(audio.suspensionState.isSuspended)"
            )
            if !audio.suspensionState.isSuspended {
                resumeBluetoothConnectionCyclesIfNeeded(reason: event.rawValue)
            }
            return
        }

        if event.isSuspending {
            if hasActiveVirtualAudioSource {
                AppLogger.shared.write(
                    "SYSTEM AUDIO suspend_deferred event=\(event.rawValue) " +
                        "bluetooth_voice=\(voiceSession.isActive) " +
                        "" +
                        "test_tone=\(isPlayingTestTone)"
                )
                return
            }
            releaseVirtualAudioOutputIfUnused(reason: "system_\(event.rawValue)")
            return
        }

        guard !audio.suspensionState.isSuspended else {
            AppLogger.shared.write(
                "SYSTEM AUDIO resume_deferred event=\(event.rawValue) " +
                    "remaining_reasons=\(audio.suspensionState.diagnostic)"
            )
            return
        }
        if hidMonitoringInterrupted { applyHIDSettings() }
        resumeVirtualAudioOutputIfNeeded(reason: "system_\(event.rawValue)")
        if BluetoothWakeRecoveryPolicy.shouldForceReconnect(event: event, started: started) {
            recoverBluetoothVoiceLink(reason: "system_wake")
        } else if BluetoothWakeRecoveryPolicy.shouldRecoverVoiceLinkAfterResume(
            started: started,
            configuredBridgeCount: connections.bridges.count,
            readyBridgeCount: readyBluetoothBridgeCount,
            voiceLinkActive: hasActiveVirtualAudioSource
        ) {
            AppLogger.shared.write(
                "SYSTEM AUDIO voice_link_recovery event=\(event.rawValue) " +
                    "cause=no_ready_bridge ready_bridges=0 " +
                    "configured_bridges=\(connections.bridges.count) " +
                    "discovery_bridge=\(connections.discoveryBridge != nil) " +
                    "audio_ready=\(isAudioOutputReady)"
            )
            recoverBluetoothVoiceLink(reason: "session_activated")
        }
        resumeBluetoothConnectionCyclesIfNeeded(reason: event.rawValue)
    }

    private func suspendActiveAudio(reason: String) {
        for bridge in connections.bridges.values { _ = bridge.requestMicrophoneClose() }
        _ = connections.discoveryBridge?.requestMicrophoneClose()
        // Hardware sleep cannot be deferred for an active voice source.
        audio.configurationGeneration &+= 1
        cancelVirtualAudioReleaseIfPending(trigger: "system_sleep")
        stopLongRecording(reason: "system_sleep")
        finishRC003VoiceExtensionTest(reason: "system_sleep")
        cancelTestToneIfNeeded(statusMessage: LocalizedMessage("audio.test_tone.cancelled_device_changed"),
            logReason: "system_sleep")
        voiceSession.pendingStart.cancel()
        voiceSession.stopRequested = false
        voiceSession.isActive = false
        voiceSession.activeDeviceIdentifier = nil
        voiceSession.commandAudio.cancel()
        voiceFnTapSession.suspend()
        releaseVoiceKeyIfNeeded()
        endVoiceSessionIfNeeded()
        audio.output.stop()
        isAudioOutputReady = false
        testToneStatus = LocalizedMessage("audio.output.none_or_unavailable")
        AppLogger.shared.write("SYSTEM AUDIO suspended event=\(reason) active_sessions_ended=true")
    }

    func configureVirtualAudioOutput(
        reason: String,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        cancelVirtualAudioReleaseIfPending(trigger: "rebind_\(reason)")
        audio.virtualAudioReleaseGeneration &+= 1
        audio.configurationGeneration &+= 1
        let generation = audio.configurationGeneration
        let deviceUID = settings.selectedAudioDeviceUID
        AppLogger.shared.write("AUDIO REBIND begin reason=\(reason) state={\(audio.output.diagnosticState())}")
        cancelTestToneIfNeeded(
            statusMessage: LocalizedMessage("audio.test_tone.cancelled_device_changed"),
            logReason: "device_reconfigure"
        )
        audio.output.configureAsync(deviceUID: deviceUID) { [weak self] configured in
            DispatchQueue.main.async {
                guard let self,
                      self.started,
                      self.audio.configurationGeneration == generation
                else {
                    completion(false)
                    return
                }
                self.audioStatus = self.audio.output.status
                self.isAudioOutputReady = self.audio.output.isReadyForTestTone
                self.testToneStatus = self.isAudioOutputReady
                    ? LocalizedMessage("audio.test_tone.ready")
                    : LocalizedMessage("audio.output.none_or_unavailable")
                AppLogger.shared.write(
                    "AUDIO REBIND finished reason=\(reason) success=\(configured) status=\(self.audioStatus.key) " +
                        "ready=\(self.isAudioOutputReady) selected_available=\(self.selectedAudioDeviceIsAvailable) " +
                        "state={\(self.audio.output.diagnosticState())}"
                )
                completion(configured)
            }
        }
    }

    @discardableResult
    func ensureVirtualAudioOutputReady(reason: String) -> Bool {
        isAudioOutputReady = audio.output.isReadyForTestTone
        guard !isAudioOutputReady else {
            AppLogger.shared.write(
                "AUDIO HEALTH ready reason=\(reason) state={\(audio.output.diagnosticState())}"
            )
            return true
        }
        AppLogger.shared.write(
            "AUDIO HEALTH stale reason=\(reason) state={\(audio.output.diagnosticState())}"
        )
        configureVirtualAudioOutput(reason: reason)
        return false
    }

    func ensureVirtualAudioOutputReady(
        reason: String,
        completion: @escaping (Bool) -> Void
    ) {
        if audio.output.isReadyForTestTone {
            isAudioOutputReady = true
            completion(true)
            return
        }
        AppLogger.shared.write(
            "AUDIO HEALTH stale reason=\(reason) state={\(audio.output.diagnosticState())}"
        )
        configureVirtualAudioOutput(reason: reason, completion: completion)
    }

    private func startObservingAudioHardware() {
        guard audio.observedHardwareAddresses.isEmpty else { return }
        audio.retainHardwareListener(audioHardwareListener)
        for selector in [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let result = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                audio.hardwareListenerQueue,
                audioHardwareListener
            )
            if result == noErr {
                audio.observedHardwareAddresses.append(address)
            } else {
                AppLogger.shared.write(
                    "AUDIO RECOVERY listener_failed selector=\(selector) " +
                        AppLogger.errorFields(domain: "os_status", code: Int(result))
                )
            }
        }
        AppLogger.shared.write("AUDIO ROUTE_MONITOR started properties=\(Self.audioHardwarePropertyNames(for: audio.observedHardwareAddresses))")
    }

    func stopObservingAudioHardware() {
        if !audio.observedHardwareAddresses.isEmpty {
            AppLogger.shared.write("AUDIO ROUTE_MONITOR stopped properties=\(Self.audioHardwarePropertyNames(for: audio.observedHardwareAddresses))")
        }
        audio.stopObservingHardware()
    }

    func scheduleAudioRecovery(reason: String, details: String = "") {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.started else { return }
            guard !self.settings.selectedAudioDeviceUID.isEmpty else {
                AppLogger.shared.write("AUDIO RECOVERY ignored reason=\(reason) detail=\(details) no_selected_device")
                return
            }
            guard !AudioHardwareChangeProperties(details: details).affectsOnlyDefaultInput else {
                self.refreshAudioDevices()
                AppLogger.shared.write(
                    "AUDIO RECOVERY ignored reason=\(reason) detail=\(details) explicit_output_unchanged"
                )
                return
            }
            let configurationHealthy = self.audio.output.isConfigurationHealthyForDiagnostics
            guard !VirtualAudioRecoveryPolicy.shouldIgnoreDefaultSystemOutputChange(
                details: details,
                configurationHealthy: configurationHealthy
            ) else {
                self.refreshAudioDevices()
                AppLogger.shared.write(
                    "AUDIO RECOVERY ignored reason=\(reason) detail=\(details) " +
                        "explicit_output_healthy=true state={\(self.audio.output.diagnosticState())}"
                )
                return
            }
            guard self.shouldKeepVirtualAudioActive else {
                self.refreshAudioDevices()
                AppLogger.shared.write(
                    "AUDIO RECOVERY ignored reason=\(reason) detail=\(details) virtual_audio_inactive"
                )
                return
            }
            self.audio.recoveryCoalescingState.recordEvent(reason: reason)
            self.audio.recoveryGeneration &+= 1
            let generation = self.audio.recoveryGeneration
            self.audio.recoveryWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      self.started,
                      self.audio.recoveryGeneration == generation
                else { return }
                let startedAtUptime = ProcessInfo.processInfo.systemUptime
                let coalesced = self.audio.recoveryCoalescingState.consumePendingEvents()
                let effectiveReason = coalesced.includesHardwareChange
                    ? "hardware_change"
                    : reason
                AppLogger.shared.write(
                    "AUDIO RECOVERY operation_id=\(generation) phase=started result=pending " +
                        "requested_reason=\(reason) effective_reason=\(effectiveReason) " +
                        "detail=\(details) coalesced_events=\(coalesced.count) " +
                        "includes_hardware_change=\(coalesced.includesHardwareChange)"
                )
                if reason == "engine_configuration_change" && !coalesced.includesHardwareChange {
                    let snapshot = self.audio.output.diagnosticSnapshot()
                    let configurationHealthy = snapshot.engineRunning &&
                        snapshot.playerPlaying &&
                        snapshot.boundToSelectedDevice == true
                    guard AudioEngineConfigurationChangePolicy.needsRecovery(
                        boundToSelectedDevice: snapshot.boundToSelectedDevice,
                        configurationHealthy: configurationHealthy,
                        hasActiveAudioSource: self.hasActiveVirtualAudioSource,
                        pendingVoiceBufferCount: snapshot.pendingBuffers
                    ) else {
                        let ignoredReason = configurationHealthy
                            ? "configuration_healthy"
                            : "still_bound_idle"
                        AppLogger.shared.write(
                            "AUDIO RECOVERY operation_id=\(generation) phase=completed result=ignored " +
                                "reason=engine_configuration_change decision=\(ignoredReason) " +
                                "detail=\(details) coalesced_events=\(coalesced.count) " +
                                "includes_hardware_change=false " +
                                "active_audio=\(self.hasActiveVirtualAudioSource) " +
                                "pending_buffers=\(snapshot.pendingBuffers) pending_samples=\(snapshot.pendingSamples) " +
                                "engine_running=\(snapshot.engineRunning) player_playing=\(snapshot.playerPlaying) " +
                                "bound_to_selected=\(self.optionalDiagnosticBool(snapshot.boundToSelectedDevice)) " +
                                "elapsed_ms=\(self.elapsedMilliseconds(since: startedAtUptime)) " +
                                "state={\(self.audio.output.diagnosticState())}"
                        )
                        self.audio.recoveryWorkItem = nil
                        return
                    }
                }
                AppLogger.shared.write(
                    "AUDIO RECOVERY operation_id=\(generation) phase=applying result=pending " +
                        "reason=\(effectiveReason) detail=\(details) " +
                        "coalesced_events=\(coalesced.count) " +
                        "includes_hardware_change=\(coalesced.includesHardwareChange) " +
                        "state={\(self.audio.output.diagnosticState())}"
                )
                self.refreshAudioDevices()
                self.applyAudioSettings(reason: "recovery_\(effectiveReason)") { [weak self] _ in
                    guard let self,
                          self.audio.recoveryGeneration == generation
                    else { return }
                    let completedSnapshot = self.audio.output.diagnosticSnapshot()
                    let ready = completedSnapshot.engineRunning &&
                        completedSnapshot.playerPlaying &&
                        completedSnapshot.boundToSelectedDevice == true
                    AppLogger.shared.write(
                        "AUDIO RECOVERY operation_id=\(generation) phase=completed " +
                            "result=\(ready ? "ready" : "degraded") reason=\(effectiveReason) " +
                            "engine_running=\(completedSnapshot.engineRunning) " +
                            "player_playing=\(completedSnapshot.playerPlaying) " +
                            "bound_to_selected=\(self.optionalDiagnosticBool(completedSnapshot.boundToSelectedDevice)) " +
                            "pending_buffers=\(completedSnapshot.pendingBuffers) " +
                            "pending_samples=\(completedSnapshot.pendingSamples) " +
                            "elapsed_ms=\(self.elapsedMilliseconds(since: startedAtUptime)) " +
                            "state={\(self.audio.output.diagnosticState())}"
                    )
                    self.audio.recoveryWorkItem = nil
                }
            }
            self.audio.recoveryWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    nonisolated static func audioHardwarePropertyNames(
        count: UInt32,
        addresses: UnsafePointer<AudioObjectPropertyAddress>
    ) -> String {
        guard count > 0 else { return "none" }
        return (0..<Int(count))
            .map { audioHardwarePropertyName(addresses[$0].mSelector) }
            .joined(separator: ",")
    }

    nonisolated static func audioHardwarePropertyNames(
        for addresses: [AudioObjectPropertyAddress]
    ) -> String {
        addresses.map { audioHardwarePropertyName($0.mSelector) }.joined(separator: ",")
    }

    nonisolated private static func audioHardwarePropertyName(
        _ selector: AudioObjectPropertySelector
    ) -> String {
        switch selector {
        case kAudioHardwarePropertyDevices:
            return "devices"
        case kAudioHardwarePropertyDefaultInputDevice:
            return "default_input"
        case kAudioHardwarePropertyDefaultOutputDevice:
            return "default_output"
        case kAudioHardwarePropertyDefaultSystemOutputDevice:
            return "default_system_output"
        default:
            return "selector_\(selector)"
        }
    }

    var canSendTestTone: Bool {
        TestToneGate.canPlay(
            hasSelectedDevice: selectedAudioDeviceIsAvailable,
            isStreaming: isStreaming,
            isPlaying: isPlayingTestTone
        )
    }

    func sendTestTone() {
        guard TestToneGate.canPlay(
            hasSelectedDevice: selectedAudioDeviceIsAvailable,
            isStreaming: isStreaming,
            isPlaying: isPlayingTestTone
        ) else {
            if isStreaming {
                testToneStatus = LocalizedMessage("audio.test_tone.blocked_voice_active")
                AppLogger.shared.write("AUDIO TEST_TONE rejected_streaming")
            } else if isPlayingTestTone {
                testToneStatus = LocalizedMessage("audio.test_tone.already_playing")
            } else {
                testToneStatus = LocalizedMessage("audio.output.none_or_unavailable")
            }
            return
        }

        cancelVirtualAudioReleaseIfPending(trigger: "test_tone_start")
        if !audio.output.isReadyForTestTone {
            ensureVirtualAudioOutputReady(reason: "test_tone") { [weak self] ready in
                self?.startTestToneAfterAudioReady(ready)
            }
            return
        }
        startTestToneAfterAudioReady(true)
    }

    func startTestToneAfterAudioReady(_ ready: Bool) {
        // A voice start or another tone may win while configuration is in flight.
        guard !isPlayingTestTone else { return }
        guard !isStreaming, !hasActiveVirtualAudioSource else {
            testToneStatus = LocalizedMessage("audio.test_tone.blocked_voice_active")
            return
        }
        guard canSendTestTone else {
            testToneStatus = LocalizedMessage("audio.output.none_or_unavailable")
            return
        }
        guard ready else {
            testToneStatus = LocalizedMessage("audio.test_tone.device_not_ready")
            releaseVirtualAudioOutputIfUnused(reason: "test_tone_configure_failed")
            return
        }
        testToneGeneration &+= 1
        let generation = testToneGeneration
        let started = audio.output.playTestTone { [weak self] finished in
            DispatchQueue.main.async {
                self?.handleTestToneCompletion(generation: generation, finished: finished)
            }
        }
        guard started else {
            testToneStatus = LocalizedMessage("audio.test_tone.device_not_ready")
            releaseVirtualAudioOutputIfUnused(reason: "test_tone_start_failed")
            return
        }
        isPlayingTestTone = true
        testToneStatus = LocalizedMessage("audio.test_tone.playing")
        AppLogger.shared.write("AUDIO TEST_TONE played")
    }

    private func handleTestToneCompletion(generation: Int, finished: Bool) {
        guard generation == testToneGeneration, isPlayingTestTone else { return }
        isPlayingTestTone = false
        testToneStatus = LocalizedMessage(finished ? "audio.test_tone.completed" : "audio.test_tone.cancelled")
        AppLogger.shared.write("AUDIO TEST_TONE \(finished ? "finished" : "cut_short")")
        releaseVirtualAudioOutputIfUnused(reason: "test_tone_finished")
    }

    func cancelTestToneIfNeeded(statusMessage: LocalizedMessage, logReason: String) {
        guard isPlayingTestTone else { return }
        testToneGeneration &+= 1
        isPlayingTestTone = false
        audio.output.cancelTestTone()
        testToneStatus = statusMessage
        AppLogger.shared.write("AUDIO TEST_TONE cancelled reason=\(logReason)")
    }
}

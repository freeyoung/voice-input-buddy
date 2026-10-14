import Combine
import Foundation

extension AppSettings {
    func setOnboardingStep(_ step: OnboardingStep) {
        guard !isOnboardingComplete, onboardingStep != step else { return }
        onboardingStep = step
    }

    func recordFirstUseEvent(
        _ kind: FirstUseEventKind,
        step: OnboardingStep,
        failureReason: FirstUseFailureReason? = nil,
        voiceAttemptID: Int? = nil,
        voiceResult: FirstUseVoiceAttemptResult? = nil,
        at date: Date = Date()
    ) {
        let stepStartedAt = defaults.object(forKey: Keys.firstUseStepStartedAt) as? Date ?? date
        let event = FirstUseEvent(
            timestamp: date,
            kind: kind,
            step: step,
            elapsedMilliseconds: max(0, Int(date.timeIntervalSince(stepStartedAt) * 1_000)),
            failureReason: failureReason,
            voiceAttemptID: voiceAttemptID,
            voiceResult: voiceResult
        )
        if kind == .blocked,
           defaults.string(forKey: Keys.firstUseLastSignature) == event.deduplicationSignature {
            return
        }
        var events = firstUseEvents
        events.append(event)
        if events.count > 100 {
            events.removeFirst(events.count - 100)
        }
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: Keys.firstUseEvents)
        }
        defaults.set(event.deduplicationSignature, forKey: Keys.firstUseLastSignature)
        if kind == .entered {
            defaults.set(date, forKey: Keys.firstUseStepStartedAt)
        }

        AppLogger.shared.write(event.runtimeLogMessage)
    }

    var firstUseEvents: [FirstUseEvent] {
        // Deliberately not reported through corruptedSettingKeys: a computed getter can run
        // many times and would append duplicates, and onboarding telemetry is not user
        // configuration that deserves a configuration-loss warning. It still logs and backs
        // up the unreadable bytes, so the loss stays recoverable.
        guard let data = defaults.data(forKey: Keys.firstUseEvents) else { return [] }
        do {
            return try JSONDecoder().decode([FirstUseEvent].self, from: data)
        } catch {
            defaults.set(data, forKey: "\(Keys.firstUseEvents).corrupt")
            AppLogger.shared.write(
                "SETTINGS decode_failed key=\(Keys.firstUseEvents) bytes=\(data.count) error=\(error)"
            )
            return []
        }
    }

    func setOnboardingVoiceTool(_ voiceTool: OnboardingVoiceTool) {
        guard onboardingVoiceTool != voiceTool else { return }
        discardOnboardingVoiceTrial()
        onboardingVoiceTool = voiceTool
        onboardingVoiceBindingPreference = .documentedDefault
        onboardingPreferredGesture = nil
        stagedVoiceToolBinding = nil
    }

    func setOnboardingVoiceBindingPreference(_ preference: OnboardingVoiceBindingPreference) {
        guard onboardingVoiceBindingPreference != preference else { return }
        discardOnboardingVoiceTrial()
        onboardingVoiceBindingPreference = preference
        stagedVoiceToolBinding = nil
    }

    func setOnboardingPreferredGesture(_ gesture: VoiceGestureMode?) {
        guard onboardingPreferredGesture != gesture else { return }
        discardOnboardingVoiceTrial()
        onboardingPreferredGesture = gesture
        stagedVoiceToolBinding = nil
    }

    func selectOnboardingDevice(_ device: PlannedRemoteDevice) {
        setOnboardingControlSource(device.onboardingSource ?? .unselected)
        onboardingDevice = device
    }

    func setOnboardingControlSource(_ source: OnboardingControlSource) {
        onboardingDevice = PlannedRemoteDevice.device(for: source)
        guard onboardingControlSource != source else { return }
        onboardingControlSource = source
        switch source {
        case .xiaomiRemote, .siriRemote, .chromecastRemote:
            onboardingRemoteAvailability = .hasRemote
        case .appleCompanion, .webRemote:
            onboardingRemoteAvailability = .noRemote
        case .unselected:
            onboardingRemoteAvailability = .unselected
        }
        discardOnboardingVoiceTrial()
    }

    func setOnboardingAppleRemoteGeneration(_ generation: OnboardingAppleRemoteGeneration?) {
        onboardingAppleRemoteGeneration = generation
        if generation != nil, onboardingControlSource != .siriRemote {
            setOnboardingControlSource(.siriRemote)
        }
    }

    func beginOnboardingVoiceTrial(_ plan: OnboardingVoicePairingPlan) {
        if defaults.data(forKey: Keys.onboardingTrialSnapshot) == nil {
            let snapshot = OnboardingVoiceConfigurationSnapshot(
                voiceKeyMode: voiceKeyMode,
                voiceFnTapModeEnabled: voiceFnTapModeEnabled,
                chromecastVoiceMode: chromecastVoiceMode
            )
            if let data = try? JSONEncoder().encode(snapshot) {
                defaults.set(data, forKey: Keys.onboardingTrialSnapshot)
            }
        }
        stagedVoiceToolBinding = plan.binding
        if let data = try? JSONEncoder().encode(plan.binding) {
            defaults.set(data, forKey: Keys.onboardingStagedVoiceBinding)
        }
        voiceKeyMode = plan.binding.shortcut
        voiceFnTapModeEnabled = plan.fnTapModeEnabled && plan.binding.shortcut == .function
        if let chromecastVoiceMode = plan.chromecastVoiceMode {
            self.chromecastVoiceMode = chromecastVoiceMode
        }
        AppLogger.shared.write(
            "ONBOARDING BINDING staged tool=\(plan.binding.tool.rawValue) " +
                "control_source=\(plan.controlSource.rawValue) " +
                "gesture=\(plan.binding.gestureMode.rawValue) " +
                "shortcut=\(plan.binding.shortcut.rawValue) " +
                "fn_tap=\(plan.fnTapModeEnabled) " +
                "binding_source=\(plan.binding.source.rawValue)"
        )
    }

    func stageLearnedOnboardingBinding(
        shortcut: VoiceKeyMode,
        gesture: VoiceGestureMode
    ) -> OnboardingVoicePairingPlan? {
        let binding = VoiceToolUserBinding(
            tool: onboardingVoiceTool,
            shortcut: shortcut,
            gestureMode: gesture,
            source: .userLearned,
            validationState: .staged,
            verifiedToolVersion: nil,
            verifiedAt: nil
        )
        guard let plan = OnboardingVoicePairingPlan.resolve(
            tool: onboardingVoiceTool,
            controlSource: onboardingControlSource,
            preferredGesture: gesture,
            userBinding: binding
        ) else { return nil }
        beginOnboardingVoiceTrial(plan)
        return plan
    }

    func verifyOnboardingVoiceBinding(at date: Date = Date()) {
        guard let stagedVoiceToolBinding else { return }
        let verified = stagedVoiceToolBinding.verified(at: date)
        verifiedVoiceToolBinding = verified
        self.stagedVoiceToolBinding = nil
        defaults.removeObject(forKey: Keys.onboardingStagedVoiceBinding)
        defaults.removeObject(forKey: Keys.onboardingTrialSnapshot)
        AppLogger.shared.write(
            "ONBOARDING BINDING verified tool=\(verified.tool.rawValue) " +
                "gesture=\(verified.gestureMode.rawValue) " +
                "shortcut=\(verified.shortcut.rawValue) " +
                "binding_source=\(verified.source.rawValue)"
        )
    }

    func discardOnboardingVoiceTrial() {
        guard let data = defaults.data(forKey: Keys.onboardingTrialSnapshot),
              let snapshot = try? JSONDecoder().decode(
                OnboardingVoiceConfigurationSnapshot.self,
                from: data
              ) else {
            stagedVoiceToolBinding = nil
            defaults.removeObject(forKey: Keys.onboardingStagedVoiceBinding)
            defaults.removeObject(forKey: Keys.onboardingTrialSnapshot)
            return
        }
        voiceKeyMode = snapshot.voiceKeyMode
        voiceFnTapModeEnabled = snapshot.voiceFnTapModeEnabled && snapshot.voiceKeyMode == .function
        chromecastVoiceMode = snapshot.chromecastVoiceMode
        stagedVoiceToolBinding = nil
        defaults.removeObject(forKey: Keys.onboardingStagedVoiceBinding)
        defaults.removeObject(forKey: Keys.onboardingTrialSnapshot)
        AppLogger.shared.write("ONBOARDING BINDING discarded reason=trial_not_verified")
    }

    func setOnboardingControlMethod(_ controlMethod: OnboardingControlMethod) {
        guard onboardingControlMethod != controlMethod else { return }
        setOnboardingControlSource(.defaultSource(for: controlMethod))
    }

    func setOnboardingRemoteAvailability(_ availability: OnboardingRemoteAvailability) {
        guard onboardingRemoteAvailability != availability else { return }
        onboardingRemoteAvailability = availability
    }

    func completeOnboarding() {
        recordFirstUseEvent(.completed, step: .complete)
        onboardingStep = .complete
        onboardingCompletedVersion = Self.currentOnboardingVersion
    }

    func restartOnboarding() {
        discardOnboardingVoiceTrial()
        verifiedVoiceToolBinding = nil
        defaults.removeObject(forKey: Keys.firstUseEvents)
        onboardingVoiceTool = .unselected
        onboardingRemoteAvailability = .unselected
        onboardingControlSource = .unselected
        onboardingDevice = nil
        onboardingAppleRemoteGeneration = nil
        onboardingVoiceBindingPreference = .documentedDefault
        onboardingPreferredGesture = nil
        onboardingStep = .permissions
        onboardingCompletedVersion = 0
        defaults.removeObject(forKey: Keys.firstUseStepStartedAt)
        defaults.removeObject(forKey: Keys.firstUseLastSignature)
    }

    static func restoreInterruptedOnboardingTrial(in defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Keys.onboardingTrialSnapshot),
              let snapshot = try? JSONDecoder().decode(
                OnboardingVoiceConfigurationSnapshot.self,
                from: data
              ) else {
            defaults.removeObject(forKey: Keys.onboardingStagedVoiceBinding)
            defaults.removeObject(forKey: Keys.onboardingTrialSnapshot)
            return
        }
        defaults.set(snapshot.voiceKeyMode.rawValue, forKey: Keys.voiceKeyMode)
        defaults.set(
            snapshot.voiceFnTapModeEnabled && snapshot.voiceKeyMode == .function,
            forKey: Keys.voiceFnTapModeEnabled
        )
        defaults.set(snapshot.chromecastVoiceMode.rawValue, forKey: Keys.chromecastVoiceMode)
        defaults.removeObject(forKey: Keys.onboardingStagedVoiceBinding)
        defaults.removeObject(forKey: Keys.onboardingTrialSnapshot)
        AppLogger.shared.write("ONBOARDING BINDING restored reason=interrupted_trial")
    }
}

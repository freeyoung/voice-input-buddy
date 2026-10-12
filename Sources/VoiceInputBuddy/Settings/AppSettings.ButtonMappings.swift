import Combine
import Foundation

extension AppSettings {
    func action(for button: RemoteButton) -> ButtonAction {
        configuredAction(for: button, trigger: .singleClick).action
    }

    func action(for button: RemoteButton, profileID: UUID?) -> ButtonAction {
        configuredAction(for: button, trigger: .singleClick, profileID: profileID).action
    }

    func setAction(_ action: ButtonAction, for button: RemoteButton) {
        buttonBindings[button] = action
    }

    func shortcut(for button: RemoteButton) -> CustomKeyboardShortcut? {
        buttonShortcuts[button]
    }

    func shortcut(for button: RemoteButton, profileID: UUID?) -> CustomKeyboardShortcut? {
        guard let profileID, profileID != selectedRemoteProfileID,
              let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
        else { return shortcut(for: button) }
        return profile.mappings.parsedButtonShortcuts[button]
    }

    func setShortcut(_ shortcut: CustomKeyboardShortcut?, for button: RemoteButton) {
        buttonShortcuts[button] = shortcut
    }

    func applicationProfileID(for button: RemoteButton) -> UUID? {
        buttonApplicationProfileIDs[button]
    }

    func applicationProfileID(for button: RemoteButton, profileID: UUID?) -> UUID? {
        guard let profileID, profileID != selectedRemoteProfileID,
              let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
        else { return applicationProfileID(for: button) }
        return profile.mappings.parsedButtonApplicationProfileIDs[button]
    }

    func allowsRapidPress(for button: RemoteButton) -> Bool {
        buttonRapidPressEnabled[button] ?? false
    }

    func allowsRapidPress(for button: RemoteButton, profileID: UUID?) -> Bool {
        guard let profileID, profileID != selectedRemoteProfileID,
              let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
        else { return allowsRapidPress(for: button) }
        return profile.mappings.parsedButtonRapidPressEnabled[button] ?? false
    }

    func setAllowsRapidPress(_ enabled: Bool, for button: RemoteButton) {
        if enabled {
            buttonRapidPressEnabled[button] = true
        } else {
            buttonRapidPressEnabled.removeValue(forKey: button)
        }
    }

    func customApplicationProfile(id: UUID?) -> CustomApplicationProfile? {
        guard let id else { return nil }
        return customApplicationProfiles.first(where: { $0.id == id })
    }

    @discardableResult
    func addCustomApplicationProfile(_ profile: CustomApplicationProfile) -> UUID {
        customApplicationProfiles.append(profile)
        return profile.id
    }

    func updateCustomApplicationProfile(_ profile: CustomApplicationProfile) {
        guard let index = customApplicationProfiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        let previous = customApplicationProfiles[index]
        customApplicationProfiles[index] = profile
        if profile.accessibilityTarget != nil && profile.accessibilityTarget != previous.accessibilityTarget {
            markPortableApplicationVerified(profile.id)
        }
    }

    func configuredBaseAction(
        for button: RemoteButton,
        trigger: ButtonTrigger
    ) -> ConfiguredButtonAction {
        if let binding = unifiedBaseBindings.first(where: {
            $0.remoteProfileID == selectedRemoteProfileID && $0.button == button && $0.trigger == trigger
        }) { return binding.configured }
        if let binding = unifiedBaseBindings.first(where: {
            $0.remoteProfileID == nil && $0.button == button && $0.trigger == trigger
        }) { return binding.configured }
        if trigger == .singleClick {
            return ConfiguredButtonAction(
                action: buttonBindings[button] ?? .disabled,
                shortcut: buttonShortcuts[button],
                applicationProfileID: applicationProfileID(for: button)
            )
        }
        return secondaryButtonBindings[button]?[trigger] ?? .disabled
    }

    func configuredBaseAction(
        for button: RemoteButton,
        trigger: ButtonTrigger,
        profileID: UUID?
    ) -> ConfiguredButtonAction {
        if let binding = unifiedBaseBindings.first(where: {
            $0.remoteProfileID == profileID && $0.button == button && $0.trigger == trigger
        }) { return binding.configured }
        if let binding = unifiedBaseBindings.first(where: {
            $0.remoteProfileID == nil && $0.button == button && $0.trigger == trigger
        }) { return binding.configured }
        guard let profileID, profileID != selectedRemoteProfileID,
              let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
        else { return configuredBaseAction(for: button, trigger: trigger) }
        let bindings = profile.mappings.parsedButtonBindings
        let shortcuts = profile.mappings.parsedButtonShortcuts
        if trigger == .singleClick {
            return ConfiguredButtonAction(
                action: bindings[button] ?? Self.defaultBindings[button] ?? .disabled,
                shortcut: shortcuts[button],
                applicationProfileID: profile.mappings.parsedButtonApplicationProfileIDs[button]
            )
        }
        return profile.mappings.parsedSecondaryButtonBindings[button]?[trigger] ?? .disabled
    }

    func configuredAction(for button: RemoteButton, trigger: ButtonTrigger) -> ConfiguredButtonAction {
        configuredAction(for: button, trigger: trigger, profileID: selectedRemoteProfileID)
    }

    func configuredAction(for button: RemoteButton, trigger: ButtonTrigger,
                          profileID: UUID?) -> ConfiguredButtonAction {
        configuredActionOverride?(profileID, button, trigger)
            ?? configuredBaseAction(for: button, trigger: trigger, profileID: profileID)
    }

    var selectedRemoteProfile: RemoteDeviceProfile? {
        guard let selectedRemoteProfileID else { return nil }
        return remoteDeviceProfiles.first(where: { $0.id == selectedRemoteProfileID })
    }

    func selectRemoteProfile(_ profileID: UUID) {
        guard profileID != selectedRemoteProfileID,
              let profile = remoteDeviceProfiles.first(where: { $0.id == profileID })
        else { return }
        isLoadingRemoteProfile = true
        selectedRemoteProfileID = profileID
        buttonBindings = Self.defaultBindings.merging(profile.mappings.parsedButtonBindings) {
            _, saved in saved
        }
        buttonShortcuts = profile.mappings.parsedButtonShortcuts
        buttonApplicationProfileIDs = profile.mappings.parsedButtonApplicationProfileIDs
        secondaryButtonBindings = profile.mappings.parsedSecondaryButtonBindings
        buttonRapidPressEnabled = profile.mappings.parsedButtonRapidPressEnabled
        isLoadingRemoteProfile = false
    }

    @discardableResult
    func registerBluetoothRemote(identifier: UUID) -> UUID {
        if let existing = remoteDeviceProfiles.first(where: { $0.bluetoothIdentifier == identifier }) {
            return existing.id
        }
        if let index = remoteDeviceProfiles.firstIndex(where: {
            $0.bluetoothIdentifier == nil && $0.model == .unknown
        }) {
            remoteDeviceProfiles[index].bluetoothIdentifier = identifier
            return remoteDeviceProfiles[index].id
        }
        let profile = RemoteDeviceProfile(
            bluetoothIdentifier: identifier,
            mappings: mappingsForNewRemote()
        )
        remoteDeviceProfiles.append(profile)
        return profile.id
    }

    @discardableResult
    func registerHIDRemote(fingerprint: String) -> UUID {
        if let existing = remoteDeviceProfiles.first(where: { $0.hidFingerprint == fingerprint }) {
            return existing.id
        }
        let selectedUnboundIndex = remoteDeviceProfiles.firstIndex(where: {
            $0.id == selectedRemoteProfileID && $0.hidFingerprint == nil
        })
        if let index = selectedUnboundIndex ?? remoteDeviceProfiles.firstIndex(where: { $0.hidFingerprint == nil }) {
            let defaultMappings = RemoteDeviceMappings(
                buttonBindings: Self.defaultBindings,
                buttonShortcuts: [:],
                secondaryButtonBindings: [:]
            )
            if remoteDeviceProfiles[index].mappings == defaultMappings,
               let configured = remoteDeviceProfiles.first(where: {
                   $0.id != remoteDeviceProfiles[index].id && $0.mappings != defaultMappings
               }) {
                remoteDeviceProfiles[index].mappings = configured.mappings
            }
            remoteDeviceProfiles[index].hidFingerprint = fingerprint
            return remoteDeviceProfiles[index].id
        }
        let profile = RemoteDeviceProfile(
            hidFingerprint: fingerprint,
            mappings: mappingsForNewRemote()
        )
        remoteDeviceProfiles.append(profile)
        return profile.id
    }

    @discardableResult
    func registerAppleSiriRemote(
        fingerprint: String,
        model: XiaomiRemoteModel = .appleSiriRemoteA2854
    ) -> UUID {
        if let existing = remoteDeviceProfiles.first(where: { $0.hidFingerprint == fingerprint }) {
            return existing.id
        }
        if let index = remoteDeviceProfiles.firstIndex(where: {
            $0.bluetoothIdentifier == nil && $0.hidFingerprint == nil && $0.model == .unknown
        }) {
            remoteDeviceProfiles[index].hidFingerprint = fingerprint
            remoteDeviceProfiles[index].model = model
            return remoteDeviceProfiles[index].id
        }
        let profile = RemoteDeviceProfile(
            model: model,
            hidFingerprint: fingerprint,
            mappings: mappingsForNewRemote()
        )
        remoteDeviceProfiles.append(profile)
        return profile.id
    }

    /// 注册 Chromecast 遥控器的设备档案。
    ///
    /// 按**型号**识别，不存任何设备标识：私有包给的 `instanceKey` 是进程内的，写进偏好会每次
    /// 启动都生成新档案，用户的映射就丢了。苹果遥控器用 HID fingerprint，本型号没有稳定的
    /// 宿主侧 HID 指纹，因此以型号为准（同时最多只有一台该型号遥控器）。
    @discardableResult
    func registerChromecastRemote() -> UUID {
        if let existing = remoteDeviceProfiles.first(where: { $0.model == .chromecastVoiceRemote }) {
            return existing.id
        }
        if let index = remoteDeviceProfiles.firstIndex(where: {
            $0.bluetoothIdentifier == nil && $0.hidFingerprint == nil && $0.model == .unknown
        }) {
            remoteDeviceProfiles[index].model = .chromecastVoiceRemote
            return remoteDeviceProfiles[index].id
        }
        let profile = RemoteDeviceProfile(
            model: .chromecastVoiceRemote,
            mappings: mappingsForNewRemote()
        )
        remoteDeviceProfiles.append(profile)
        return profile.id
    }

    func profileID(forBluetoothIdentifier identifier: UUID) -> UUID? {
        remoteDeviceProfiles.first(where: { $0.bluetoothIdentifier == identifier })?.id
    }

    func profileID(forHIDFingerprint fingerprint: String) -> UUID? {
        remoteDeviceProfiles.first(where: { $0.hidFingerprint == fingerprint })?.id
    }

    func bindHIDFingerprint(_ fingerprint: String, to profileID: UUID) {
        guard let index = remoteDeviceProfiles.firstIndex(where: { $0.id == profileID }) else { return }
        for candidate in remoteDeviceProfiles.indices where remoteDeviceProfiles[candidate].hidFingerprint == fingerprint {
            remoteDeviceProfiles[candidate].hidFingerprint = nil
        }
        remoteDeviceProfiles[index].hidFingerprint = fingerprint
    }

    private func mappingsForNewRemote() -> RemoteDeviceMappings {
        selectedRemoteProfile?.mappings ?? RemoteDeviceMappings(
            buttonBindings: buttonBindings,
            buttonShortcuts: buttonShortcuts,
            buttonApplicationProfileIDs: buttonApplicationProfileIDs,
            secondaryButtonBindings: secondaryButtonBindings,
            buttonRapidPressEnabled: buttonRapidPressEnabled
        )
    }

    func updateRemoteProfile(
        _ profileID: UUID,
        model: XiaomiRemoteModel,
        customName: String
    ) {
        guard let index = remoteDeviceProfiles.firstIndex(where: { $0.id == profileID }) else { return }
        remoteDeviceProfiles[index].model = model
        remoteDeviceProfiles[index].customName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The system name is a display cache, never a device identity or a stored numbered label.
    @discardableResult
    func updateRemoteProfileSystemName(
        _ profileID: UUID,
        name: String?,
        serialNumber: String? = nil
    ) -> Bool {
        guard let index = remoteDeviceProfiles.firstIndex(where: { $0.id == profileID }),
              let customName = RemoteDeviceNamePolicy.customName(
                from: name, model: remoteDeviceProfiles[index].model, serialNumber: serialNumber
              ),
              remoteDeviceProfiles[index].customName != customName
        else { return false }
        remoteDeviceProfiles[index].customName = customName
        return true
    }

    func updateRemoteProfileModel(_ profileID: UUID, model: XiaomiRemoteModel) {
        guard model != .unknown,
              let index = remoteDeviceProfiles.firstIndex(where: { $0.id == profileID }),
              remoteDeviceProfiles[index].model != model
        else { return }
        remoteDeviceProfiles[index].model = model
    }

    func setAction(_ action: ButtonAction, for button: RemoteButton, trigger: ButtonTrigger) {
        guard trigger != .singleClick else {
            setAction(action, for: button)
            return
        }

        var bindings = secondaryButtonBindings[button] ?? [:]
        let shortcut = bindings[trigger]?.shortcut
        let applicationProfileID = bindings[trigger]?.applicationProfileID
        bindings[trigger] = ConfiguredButtonAction(
            action: action,
            shortcut: shortcut,
            applicationProfileID: applicationProfileID
        )
        secondaryButtonBindings[button] = bindings.isEmpty ? nil : bindings
    }

    func setApplicationProfileID(
        _ applicationProfileID: UUID?,
        for button: RemoteButton,
        trigger: ButtonTrigger
    ) {
        guard trigger != .singleClick else {
            buttonApplicationProfileIDs[button] = applicationProfileID
            return
        }
        guard var bindings = secondaryButtonBindings[button], var binding = bindings[trigger] else {
            return
        }
        binding.applicationProfileID = applicationProfileID
        bindings[trigger] = binding
        secondaryButtonBindings[button] = bindings
    }

    func setShortcut(
        _ shortcut: CustomKeyboardShortcut?,
        for button: RemoteButton,
        trigger: ButtonTrigger
    ) {
        guard trigger != .singleClick else {
            setShortcut(shortcut, for: button)
            return
        }
        guard var bindings = secondaryButtonBindings[button], var binding = bindings[trigger] else {
            return
        }
        binding.shortcut = shortcut
        bindings[trigger] = binding
        secondaryButtonBindings[button] = bindings
    }

    func hasSecondaryAction(for button: RemoteButton) -> Bool {
        [.doubleClick, .longPress].contains { trigger in
            configuredAction(for: button, trigger: trigger).action != .disabled
        }
    }

    func hasSecondaryAction(for button: RemoteButton, profileID: UUID?) -> Bool {
        [.doubleClick, .longPress].contains { trigger in
            configuredAction(for: button, trigger: trigger, profileID: profileID).action != .disabled
        }
    }

    func setExperimentalContinuousRecordingEnabled(_ enabled: Bool) {
        let backup = enabled
            ? continuousRecordingPowerBindingBackup ?? configuredAction(for: .power, trigger: .singleClick)
            : continuousRecordingPowerBindingBackup
        applyContinuousRecordingExperimentState(enabled: enabled, backup: backup)
    }

    func resetBindings() {
        buttonBindings = Self.defaultBindings
        buttonShortcuts = [:]
        unifiedBaseBindings.removeAll { $0.remoteProfileID == selectedRemoteProfileID }
        // Legacy unscoped macros remain available on other devices after this reset.
        if let device = selectedRemoteProfileID {
            for inherited in unifiedBaseBindings.filter({ $0.remoteProfileID == nil }) {
                setBaseBinding(ConfiguredButtonAction(
                    action: inherited.trigger == .singleClick ? Self.defaultBindings[inherited.button] ?? .disabled : .disabled,
                    shortcut: nil), for: inherited.button, trigger: inherited.trigger, profileID: device)
            }
        }
        buttonApplicationProfileIDs = [:]
        secondaryButtonBindings = [:]
        buttonRapidPressEnabled = [:]
        if experimentalContinuousRecordingEnabled {
            continuousRecordingPowerBindingBackup = ConfiguredButtonAction(
                action: .escape,
                shortcut: nil
            )
            setAction(.toggleLongRecording, for: .power, trigger: .singleClick)
        }
    }
}

extension AppSettings {
    static let defaultBindings: [RemoteButton: ButtonAction] = [
        .power: .escape,
        .up: .arrowUp,
        .left: .arrowLeft,
        .ok: .returnKey,
        .right: .arrowRight,
        .down: .arrowDown,
        .back: .deleteBackward,
        .volumeUp: .volumeUp,
        .home: .showDesktop,
        .volumeDown: .volumeDown,
        .menu: .contextMenu,
        .tv: .appSwitcher,
        .playPause: .playPause,
        .mute: .volumeMute,
    ]
}

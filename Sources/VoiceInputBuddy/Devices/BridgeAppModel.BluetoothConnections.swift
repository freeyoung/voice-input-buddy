import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    var selectedBluetoothBridge: XiaomiBluetoothBridge? {
        guard let identifier = settings.selectedRemoteProfile?.bluetoothIdentifier else { return nil }
        return bluetoothBridges[identifier]
    }

    func startBluetoothConnections() {
        let identifiers = Set(settings.remoteDeviceProfiles.compactMap(\.bluetoothIdentifier))
        for identifier in identifiers where bluetoothBridges[identifier] == nil {
            let bridge = XiaomiBluetoothBridge(
                settings: settings,
                delegate: self,
                targetIdentifier: identifier
            )
            bluetoothBridges[identifier] = bridge
            bridge.setSystemSuspended(
                systemAudioSuspensionState.isSuspended,
                reason: "bridge_start"
            )
            bridge.start()
        }
        startBluetoothDiscoveryIfNeeded()
    }

    func startBluetoothDiscoveryIfNeeded() {
        guard started, discoveryBluetoothBridge == nil else { return }
        let bridge = XiaomiBluetoothBridge(
            settings: settings,
            delegate: self,
            excludedIdentifiers: { [weak self] in
                guard let self else { return [] }
                return Set(self.bluetoothBridges.keys)
            }
        )
        discoveryBluetoothBridge = bridge
        bridge.setSystemSuspended(
            systemAudioSuspensionState.isSuspended,
            reason: "bridge_start"
        )
        bridge.start()
    }

    func registerBluetoothBridgeIfNeeded(_ bridge: XiaomiBluetoothBridge) -> UUID? {
        guard let identifier = bluetoothIdentifier(for: bridge) else { return nil }
        let existingProfileID = settings.profileID(forBluetoothIdentifier: identifier)
        let profileID = existingProfileID ?? settings.registerBluetoothRemote(identifier: identifier)
        if discoveryBluetoothBridge === bridge {
            discoveryBluetoothBridge = nil
            bluetoothBridges[identifier] = bridge
            startBluetoothDiscoveryIfNeeded()
        } else if bluetoothBridges[identifier] == nil {
            bluetoothBridges[identifier] = bridge
        }
        applyPendingRemoteTelemetry(identifier: identifier, profileID: profileID)
        AppLogger.shared.write(
            "REMOTE PROFILE phase=completed result=persisted reason=verified_remote_path " +
                "created=\(existingProfileID == nil)"
        )
        return profileID
    }

    private func applyPendingRemoteTelemetry(identifier: UUID, profileID: UUID) {
        let hadBattery = pendingRemoteBatteryLevels[identifier] != nil
        let hadPower = pendingRemotePowerStates[identifier] != nil
        let hadModel = pendingRemoteModels[identifier] != nil
        if let level = pendingRemoteBatteryLevels.removeValue(forKey: identifier) {
            remoteBatteryLevels[profileID] = min(100, max(0, level))
        }
        if let powerState = pendingRemotePowerStates.removeValue(forKey: identifier) {
            remotePowerStates[profileID] = powerState
        }
        if let model = pendingRemoteModels.removeValue(forKey: identifier) {
            settings.updateRemoteProfileModel(profileID, model: model)
            refreshRemoteDeviceNames(reason: .connection)
        }
        if hadBattery || hadPower || hadModel {
            AppLogger.shared.write(
                "REMOTE PROFILE_TELEMETRY phase=completed result=applied reason=profile_ready " +
                    "battery=\(hadBattery) power=\(hadPower) model=\(hadModel)"
            )
        }
    }

    func bluetoothIdentifier(for bridge: XiaomiBluetoothBridge) -> UUID? {
        bridge.deviceIdentifier ?? bluetoothBridges.first(where: { $0.value === bridge })?.key
    }

    func remoteProfileID(for bridge: XiaomiBluetoothBridge) -> UUID? {
        guard let identifier = bluetoothIdentifier(for: bridge) else { return nil }
        return settings.profileID(forBluetoothIdentifier: identifier)
    }

    func selectRemoteProfile(_ profileID: UUID) {
        settings.selectRemoteProfile(profileID)
        refreshAppleRemoteHIDStatus()
        refreshBluetoothPresentation()
    }

    func selectDefaultMappingRemoteIfAvailable() {
        let localization = LocalizationStore(settings: settings)
        let connectedProfiles = RemoteDeviceNamePolicy.sortedForCards(
            settings.remoteDeviceProfiles.filter { isRemoteConnected($0.id) },
            modelName: { profile in
                RemoteDeviceNamePolicy.displayName(
                    for: profile,
                    among: self.settings.remoteDeviceProfiles,
                    defaultName: localization.text(profile.model.localizationKey)
                )
            },
            systemName: { self.systemDeviceName(for: $0) }
        )
        guard let profile = RemoteDeviceNamePolicy.defaultMappingProfile(
            from: connectedProfiles
        ) else {
            AppLogger.shared.write(
                "REMOTE MAPPING_DEFAULT phase=completed result=preserved " +
                    "reason=xiaomi_unavailable"
            )
            return
        }
        guard profile.id != settings.selectedRemoteProfileID else {
            AppLogger.shared.write(
                "REMOTE MAPPING_DEFAULT phase=completed result=preserved " +
                    "reason=xiaomi_already_selected"
            )
            return
        }
        AppLogger.shared.write(
            "REMOTE MAPPING_DEFAULT phase=completed result=selected " +
                "reason=xiaomi_default family=xiaomi"
        )
#if DEBUG
        if ProcessInfo.processInfo.environment["VOICE_INPUT_BUDDY_SETTINGS_SCREENSHOT_DIR"] != nil {
            settings.selectRemoteProfile(profile.id)
            return
        }
#endif
        selectRemoteProfile(profile.id)
    }

    func activateRemoteProfile(for bridge: XiaomiBluetoothBridge) -> UUID? {
        guard let profileID = registerBluetoothBridgeIfNeeded(bridge) else { return nil }
        selectRemoteProfile(profileID)
        return profileID
    }

    /// Refresh display metadata without starting discovery, reconnecting, or changing device identity.
    func refreshRemoteDeviceNames(reason: RemoteDeviceNameRefreshReason) {
        guard started, CBManager.authorization == .allowedAlways else { return }
        remoteDeviceNameRefreshOperation &+= 1
        var requested = 0
        var resolved = 0
        var changed = 0
        for (identifier, bridge) in bluetoothBridges {
            guard let profileID = settings.profileID(forBluetoothIdentifier: identifier),
                  connectedRemoteProfileIDs.contains(profileID)
            else { continue }
            requested += 1
            bridge.refreshBatteryTelemetry(reason: reason.rawValue)
            let name = bridge.currentSystemDeviceName()
            if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolved += 1
            }
            if let name = RemoteDeviceNamePolicy.observedSystemName(from: name) {
                remoteSystemDeviceNames[profileID] = name
            }
            if settings.updateRemoteProfileSystemName(profileID, name: name) { changed += 1 }
        }
        let appleProfiles = settings.remoteDeviceProfiles.filter {
            connectedAppleRemoteProfileIDs.contains($0.id)
        }
        if !appleProfiles.isEmpty {
            let names = RemoteDeviceNameReader.readHIDNames()
            for profile in appleProfiles {
                requested += 1
                let observation = profile.hidFingerprint.flatMap { names[$0] }
                let name = observation?.name
                if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    resolved += 1
                }
                if let name = RemoteDeviceNamePolicy.observedSystemName(from: name) {
                    remoteSystemDeviceNames[profile.id] = name
                }
                if settings.updateRemoteProfileSystemName(
                    profile.id, name: name, serialNumber: observation?.serialNumber
                ) { changed += 1 }
            }
        }
        AppLogger.shared.write(
            "REMOTE NAME REFRESH operation_id=\(remoteDeviceNameRefreshOperation) " +
                "phase=completed reason=\(reason.rawValue) requested=\(requested) " +
                "resolved=\(resolved) changed=\(changed) unavailable=\(requested - resolved)"
        )
    }

    func refreshBluetoothPresentation() {
        let allStates = bluetoothBridgeStates.values
        let connectedBluetoothProfileIDs = Set<UUID>(bluetoothBridges.compactMap { identifier, bridge in
            guard let profileID = settings.profileID(forBluetoothIdentifier: identifier),
                  let state = bluetoothBridgeStates[ObjectIdentifier(bridge)],
                  case .ready = state
            else { return nil }
            return profileID
        })
        connectedRemoteProfileIDs = connectedBluetoothProfileIDs
            .union(connectedAppleRemoteProfileIDs)
            .union(connectedChromecastProfileIDs)
        let bluetoothIsReady = allStates.contains { state in
            if case .ready = state { return true }
            return false
        }
        isConnected = bluetoothIsReady
            || !connectedAppleRemoteProfileIDs.isEmpty
            || !connectedChromecastProfileIDs.isEmpty
        if let selectedRemoteProfileID = settings.selectedRemoteProfileID,
           connectedAppleRemoteProfileIDs.contains(selectedRemoteProfileID) {
            connectionStatus = LocalizedMessage("connection.status.apple_remote_connected")
        } else if let selectedRemoteProfileID = settings.selectedRemoteProfileID,
                  connectedChromecastProfileIDs.contains(selectedRemoteProfileID) {
            connectionStatus = LocalizedMessage("connection.status.chromecast_connected")
        } else if let selectedBluetoothBridge,
           let state = bluetoothBridgeStates[ObjectIdentifier(selectedBluetoothBridge)] {
            connectionStatus = state.message
        } else if let ready = allStates.first(where: { state in
            if case .ready = state { return true }
            return false
        }) {
            connectionStatus = ready.message
        } else if !connectedAppleRemoteProfileIDs.isEmpty {
            connectionStatus = LocalizedMessage("connection.status.apple_remote_connected")
        } else if !connectedChromecastProfileIDs.isEmpty {
            connectionStatus = LocalizedMessage("connection.status.chromecast_connected")
        } else if let state = allStates.first {
            connectionStatus = state.message
        } else {
            connectionStatus = LocalizedMessage("connection.status.searching")
        }
    }
}

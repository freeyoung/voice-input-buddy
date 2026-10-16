import Foundation

extension BridgeAppModel {
    func rebindRemote(profileID: UUID, to replacementProfileID: UUID) -> Bool {
        guard !hasActiveVirtualAudioSource, !voiceKeyLatch.isHeld,
              !voiceFnTapSession.requiresCleanupBeforeMapping,
              voiceSession.pendingStart.identifier == nil,
              !isRemoteConnected(profileID), isRemoteConnected(replacementProfileID),
              let original = settings.remoteDeviceProfiles.first(where: { $0.id == profileID }),
              let replacement = settings.remoteDeviceProfiles.first(where: { $0.id == replacementProfileID }),
              let identifier = replacement.bluetoothIdentifier,
              let bridge = connections.bridges[identifier], case .ready = bridge.state,
              settings.rebindBluetoothRemote(profileID: profileID, to: replacementProfileID) else { return false }
        if let oldIdentifier = original.bluetoothIdentifier {
            if let oldBridge = connections.bridges.removeValue(forKey: oldIdentifier) {
                oldBridge.stop()
                connections.states.removeValue(forKey: ObjectIdentifier(oldBridge))
            }
            remoteDeviceInformation.removeValue(forKey: oldIdentifier)
            pendingRemoteBatteryLevels.removeValue(forKey: oldIdentifier)
            pendingRemotePowerStates.removeValue(forKey: oldIdentifier)
            pendingRemoteModels.removeValue(forKey: oldIdentifier)
        }
        remoteBatteryLevels.removeValue(forKey: replacementProfileID)
        remotePowerStates.removeValue(forKey: replacementProfileID)
        remoteSystemDeviceNames.removeValue(forKey: replacementProfileID)
        refreshBluetoothPresentation()
        learnSelectedRemoteHIDIdentity(bridge)
        applyHIDSettings()
        bridge.refreshBatteryTelemetry(reason: "remote_rebound")
        refreshRemoteDeviceNames(reason: .connection)
        AppLogger.shared.write("REMOTE REBIND phase=completed result=bound mappings_preserved=true")
        return true
    }
}

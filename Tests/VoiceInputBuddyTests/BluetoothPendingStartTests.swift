import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Bluetooth pending start isolation")
@MainActor
struct BluetoothPendingStartTests {
    @Test func busyRemoteDoesNotRegisterOrSelectTheRejectedDevice() throws {
        let suite = "bluetooth-busy-selection-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let model = BridgeAppModel(settings: settings)
        let owner = UUID(), rejected = UUID()
        let selected = settings.registerBluetoothRemote(identifier: owner)
        settings.selectRemoteProfile(selected)
        model.voiceSession.activeDeviceIdentifier = owner
        model.voiceSession.isActive = true
        let bridge = BluetoothRemoteBridge(settings: settings, delegate: model, targetIdentifier: rejected)
        model.bluetoothBridgeDidStartVoice(bridge)
        #expect(settings.selectedRemoteProfileID == selected)
        #expect(settings.profileID(forBluetoothIdentifier: rejected) == nil)
        #expect(model.voiceSession.activeDeviceIdentifier == owner)
        #expect(model.voiceSession.isActive)
        #expect(model.voiceSession.pendingStart.identifier == nil)
    }

    @Test func oldConfigurationCompletionCannotConsumeRestartedAudio() {
        let pending = BluetoothPendingAudioStart()
        let device = UUID()
        let old = pending.begin(for: device)
        let acceptedOldAudio = pending.audio.appendIfWaiting([1, 2])
        #expect(acceptedOldAudio)
        #expect(pending.cancel(ifOwnedBy: device))
        let current = pending.begin(for: device)
        let acceptedCurrentAudio = pending.audio.appendIfWaiting([3, 4])
        #expect(acceptedCurrentAudio)
        #expect(!pending.matches(identifier: device, operationID: old))
        #expect(pending.matches(identifier: device, operationID: current))
        #expect(pending.drain() == [3, 4])
        #expect(!pending.matches(identifier: device, operationID: current))
    }

    @Test func disconnectClearsOnlyThePendingStartOwnedByThatBridge() throws {
        let suite = "bluetooth-pending-disconnect-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let model = BridgeAppModel(settings: settings)
        let owner = UUID()
        let bridge = BluetoothRemoteBridge(settings: settings, delegate: model, targetIdentifier: owner)
        let other = BluetoothRemoteBridge(settings: settings, delegate: model, targetIdentifier: UUID())
        model.voiceSession.pendingStart.begin(for: owner)
        model.voiceSession.stopRequested = true
        let accepted = model.voiceSession.pendingStart.audio.appendIfWaiting([1, 2])
        #expect(accepted)
        model.bluetoothBridge(other, didChange: .reconnecting)
        #expect(model.voiceSession.pendingStart.identifier == owner)
        #expect(model.voiceSession.stopRequested)
        model.bluetoothBridge(bridge, didChange: .reconnecting)
        #expect(model.voiceSession.pendingStart.identifier == nil)
        #expect(!model.voiceSession.stopRequested)
        #expect(model.voiceSession.pendingStart.drain().isEmpty)
    }
}

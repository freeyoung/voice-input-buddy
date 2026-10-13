import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Bluetooth pending start isolation")
@MainActor
struct BluetoothPendingStartTests {
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
        let bridge = XiaomiBluetoothBridge(settings: settings, delegate: model, targetIdentifier: owner)
        let other = XiaomiBluetoothBridge(settings: settings, delegate: model, targetIdentifier: UUID())
        model.pendingBluetoothVoiceStart.begin(for: owner)
        model.pendingBluetoothVoiceStopRequested = true
        let accepted = model.pendingBluetoothVoiceStart.audio.appendIfWaiting([1, 2])
        #expect(accepted)
        model.bluetoothBridge(other, didChange: .reconnecting)
        #expect(model.pendingBluetoothVoiceStart.identifier == owner)
        #expect(model.pendingBluetoothVoiceStopRequested)
        model.bluetoothBridge(bridge, didChange: .reconnecting)
        #expect(model.pendingBluetoothVoiceStart.identifier == nil)
        #expect(!model.pendingBluetoothVoiceStopRequested)
        #expect(model.pendingBluetoothVoiceStart.drain().isEmpty)
    }
}

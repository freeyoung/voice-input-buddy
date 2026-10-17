import Foundation

/// Main-queue owner of configured and discovery connections.
@MainActor
final class BluetoothConnectionRegistry {
    var bridges: [UUID: XiaomiBluetoothBridge] = [:]
    var states: [ObjectIdentifier: BluetoothBridgeState] = [:]
    var discoveryBridge: XiaomiBluetoothBridge?

    var readyCount: Int {
        states.values.reduce(into: 0) { count, state in
            if case .ready = state { count += 1 }
        }
    }

    func stopAll() {
        bridges.values.forEach { $0.stop() }
        discoveryBridge?.stop()
        bridges.removeAll()
        states.removeAll()
        discoveryBridge = nil
    }
}

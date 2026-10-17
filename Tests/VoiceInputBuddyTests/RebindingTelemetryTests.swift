import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Rebinding telemetry") @MainActor
struct RebindingTelemetryTests {
    @Test func transferUsesCurrentConnectionAndInvalidatesStaleOriginalValues() throws {
        let name = "telemetry-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: defaults))
        let old = UUID(), replacement = UUID()
        model.remoteBatteryLevels = [old: 2, replacement: 78]
        model.remotePowerStates = [old: .onBattery, replacement: .charging]
        model.transferRemoteTelemetry(from: replacement, to: old)
        #expect(model.remoteBatteryLevels[old] == 78)
        #expect(model.remotePowerStates[old] == .charging)
        #expect(model.remotePowerStates[replacement] == nil)
        #expect(model.remoteBatteryLevels[replacement] == nil)
        model.transferRemoteTelemetry(from: replacement, to: old)
        #expect(model.remoteBatteryLevels[old] == nil)
        #expect(model.remotePowerStates[old] == nil)
    }
}

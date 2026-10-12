import AppKit
import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Reviewed runtime boundaries")
@MainActor
struct ReviewRuntimeRegressionTests {
    private func values() -> (UserDefaults, String) {
        let name = "review-runtime-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test(arguments: [OnboardingStep.remote, .controls])
    func validationObservesButtonsWithoutExecutingConfiguredActions(step: OnboardingStep) {
        let (defaults, name) = values()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        settings.setAction(.commandQuit, for: .right)
        let profile = UUID()
        var observed = 0
        var actions = 0
        let monitor = HIDRemoteMonitor(settings: settings, profileID: profile,
            runtimePermissions: { true }, actionPerformer: { _, _, _ in actions += 1; return true },
            diagnosticLogger: { _ in })
        monitor.onButtonPressed = { _, _, _ in
            observed += 1
            return (profile, !OnboardingControlValidationPolicy.suppressConfiguredActions(at: step, source: .xiaomiRemote))
        }
        monitor.connectSimulatedDevice(fingerprint: "test", profileID: profile)
        let usage = RemoteButton.right.hidUsage
        monitor.handleSimulatedReport(reportID: 1, data: Data([UInt8(usage & 255), UInt8(usage >> 8)]))
        monitor.handleSimulatedReport(reportID: 1, data: Data([0, 0]))
        #expect(observed == 1)
        #expect(actions == 0)
        monitor.disconnectSimulatedDevice()
        #expect(!OnboardingControlValidationPolicy.suppressConfiguredActions(at: .voiceTest, source: .xiaomiRemote))
    }

    @Test func resetPreservesReleaseOfNativePassthroughArrow() throws {
        let (defaults, name) = values()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        let filter = KeyboardEventSuppressor(uptime: { 0 })
        let profile = UUID()
        let monitor = HIDRemoteMonitor(settings: settings, profileID: profile,
            eventSuppressor: filter, ownsEventSuppressor: false,
            runtimePermissions: { true }, diagnosticLogger: { _ in })
        monitor.connectSimulatedDevice(fingerprint: "test", profileID: profile, isSeized: false)
        let usage = RemoteButton.right.hidUsage
        monitor.handleSimulatedReport(reportID: 1, data: Data([UInt8(usage & 255), UInt8(usage >> 8)]))
        let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true))
        #expect(!filter.handle(type: .keyDown, event: down))
        monitor.cancelMappingInteractions()
        let up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: false))
        #expect(!filter.handle(type: .keyUp, event: up))
        monitor.disconnectSimulatedDevice()
    }

    @Test func retiredStatisticsArePurgedWithoutReadingThem() {
        let (defaults, name) = values()
        defer { defaults.removePersistentDomain(forName: name) }
        let keys = ["usage.totalButtonPressCount", "usage.totalVoiceDuration", "usage.dailyStatistics", "usage.voiceSessionRanking"]
        for key in keys { defaults.set(Data([255]), forKey: key); defaults.set(Data([255]), forKey: key + ".corrupt") }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.totalButtonPressCount == 0)
        #expect(settings.totalVoiceDuration == 0)
        #expect(settings.dailyStatistics.isEmpty)
        #expect(settings.voiceSessionRanking.isEmpty)
        #expect(settings.corruptedSettingKeys.isEmpty)
        settings.recordButtonPress()
        for key in keys { #expect(defaults.object(forKey: key) == nil); #expect(defaults.object(forKey: key + ".corrupt") == nil) }
    }

    @Test func v1ImportReplacesExistingUnifiedOverrides() throws {
        let (defaults, name) = values()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        var object = try #require(JSONSerialization.jsonObject(with: settings.exportedConfigurationData()) as? [String: Any])
        object["formatVersion"] = 1
        object.removeValue(forKey: "unifiedBaseBindings")
        settings.setBaseBinding(ConfiguredButtonAction(action: .commandQuit, shortcut: nil), for: .right, trigger: .singleClick, profileID: nil)
        #expect(settings.configuredBaseAction(for: .right, trigger: .singleClick).action == .commandQuit)
        try settings.importConfiguration(from: JSONSerialization.data(withJSONObject: object))
        #expect(settings.unifiedBaseBindings.isEmpty)
        #expect(settings.configuredBaseAction(for: .right, trigger: .singleClick).action == .arrowRight)
    }

    @Test func disablingMappingRestoresPreviousActionAndSensibleDefaults() {
        let previous = ConfiguredButtonAction(action: .commandCopy, shortcut: nil)
        #expect(MappingDisablePolicy.configuration(disabling: true, current: previous, backup: nil, button: .right, trigger: .singleClick) == .disabled)
        #expect(MappingDisablePolicy.configuration(disabling: false, current: .disabled, backup: previous, button: .right, trigger: .singleClick) == previous)
        #expect(MappingDisablePolicy.configuration(disabling: false, current: .disabled, backup: nil, button: .right, trigger: .singleClick).action == .arrowRight)
        let empty = MappingDisablePolicy.configuration(disabling: false, current: .disabled, backup: nil, button: .right, trigger: .doubleClick)
        #expect(empty.action == .customShortcut && empty.shortcut == nil)
    }

    @Test func hciTimeoutAndFailurePermitRetryAndIgnoreLateCallbacks() {
        var timeouts: [() -> Void] = []
        var replies: [(Bool, String) -> Void] = []
        var results: [AppleRemoteHCIConfigurationClient.Result] = []
        let client = AppleRemoteHCIConfigurationClient(scheduleTimeout: { timeouts.append($0) }, requestPreparation: { _, reply in replies.append(reply) })
        client.prepare { results.append($0) }
        timeouts[0]()
        #expect(results == [.failed("hci_helper_timed_out")])
        client.prepare { results.append($0) }
        #expect(replies.count == 2)
        replies[0](true, "late_success")
        replies[1](false, "rejected")
        #expect(results == [.failed("hci_helper_timed_out"), .failed("rejected")])
        client.prepare { results.append($0) }
        #expect(replies.count == 3)
        replies[2](true, "ready")
        #expect(results.last == .ready)
        client.stop()
    }

    @Test func corruptedMappingsAreReportedAndPreservedWhileDefaultsRecover() {
        let (defaults, name) = values()
        defer { defaults.removePersistentDomain(forName: name) }
        let corrupt = Data("not json".utf8)
        defaults.set(corrupt, forKey: "buttonBindings")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.corruptedSettingKeys.contains("buttonBindings"))
        #expect(defaults.data(forKey: "buttonBindings.corrupt") == corrupt)
        #expect(settings.action(for: .right) == .arrowRight)
        settings.setAction(.commandCopy, for: .right)
        let recovered = AppSettings(defaults: defaults)
        #expect(!recovered.corruptedSettingKeys.contains("buttonBindings"))
        #expect(recovered.action(for: .right) == .commandCopy)
        #expect(defaults.data(forKey: "buttonBindings.corrupt") == corrupt)
    }

    @Test func oversizedConfigurationIsRejectedBeforeReadingOrDecoding() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let data = Data(repeating: 32, count: ConfigurationFileReader.maximumBytes + 1)
        try data.write(to: file)
        #expect(throws: AppConfigurationError.self) { try ConfigurationFileReader.read(from: file) }
        #expect(throws: AppConfigurationError.self) { try AppSettings.validatedConfiguration(from: data) }
        try Data("small".utf8).write(to: file)
        #expect(try ConfigurationFileReader.read(from: file) == Data("small".utf8))
    }
    @Test func focusInputWaitsForActualFocusCompletionEvenIfOldFieldWasEditable() {
        let snapshot = VoiceInputDestinationSnapshot(bundleIdentifier: "example.editor", role: "AXTextArea", subrole: "", enabled: true, editable: true, protectedContent: false, semanticText: "Composer", focusIdentity: "old")
        let coordinator = VoiceInputDestinationCoordinator(schedule: { _, _ in VoiceFnTapScheduledTask(cancellation: {}) }, snapshot: { snapshot })
        let intent = VoiceInputDestinationIntent.resolve(configured: .init(action: .focusInput, shortcut: nil), applicationProfile: nil)
        #expect(intent == .focusInput)
        let id = coordinator.beginTargetSwitch(intent: .focusInput)
        var result: VoiceInputDestinationWaitResult?
        if case .waiting = coordinator.waitUntilReady(completion: { result = $0 }) {} else { Issue.record("Must wait for the focus callback") }
        #expect(result == nil)
        coordinator.completeFocusOperation(requestID: id + 1, succeeded: true)
        #expect(result == nil)
        coordinator.completeFocusOperation(requestID: id, succeeded: true)
        #expect(result == .ready)
        let failed = coordinator.beginTargetSwitch(intent: .focusInput)
        _ = coordinator.waitUntilReady { result = $0 }
        coordinator.completeFocusOperation(requestID: failed, succeeded: false)
        #expect(result == .cancelled(.actionFailed))
    }

    @Test func deferredVoiceStopsRemainBoundToTheirOwnDevice() {
        var stops = DeviceVoiceStopRequests<String>()
        stops.request("first")
        #expect(stops.take(pending: ["second"]).isEmpty)
        #expect(stops.take(pending: ["first", "second"]) == ["first"])
        stops.request("first")
        stops.cancel("first") // pressed again before setup completed
        #expect(stops.take(pending: ["first"]).isEmpty)
        stops.request("second")
        stops.removeAll()
        #expect(stops.take(pending: ["second"]).isEmpty)
    }

    @Test func hciDisconnectionAfterReadyAllowsAnotherPreparation() async {
        var connections: [NSXPCConnection] = []
        let client = AppleRemoteHCIConfigurationClient(scheduleTimeout: { _ in }, requestPreparation: { connection, reply in
            connections.append(connection)
            reply(true, "ready")
        })
        client.prepare { #expect($0 == .ready) }
        connections[0].invalidationHandler?()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        client.prepare { #expect($0 == .ready) }
        #expect(connections.count == 2)
        client.stop()
    }

}

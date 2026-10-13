import AppKit
import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Runtime operation lifecycle")
@MainActor
struct RuntimeOperationLifecycleTests {
    @Test(arguments: [false, true])
    func cancelledRecorderDiscardsQueuedCapture(reset: Bool) throws {
        var pending: [() -> Void] = []
        var captured: [CustomKeyboardShortcut] = []
        let monitor = ShortcutCaptureMonitor(onCapture: { captured.append($0) },
            accessibilityTrusted: { true }, modifierIsPressed: { _ in false },
            dispatchCallback: { pending.append($0) })
        monitor.resetCaptureState()
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true))
        #expect(monitor.handle(type: .keyDown, event: key))
        #expect(pending.count == 1)
        if reset { monitor.resetCaptureState() } else { monitor.stop() }
        pending.removeFirst()()
        #expect(captured.isEmpty)
    }

    @Test func staleAudioStartupCannotStopNewSession() async throws {
        let name = "operation-lifecycle-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let model = BridgeAppModel(settings: AppSettings(defaults: values))
        model.started = true
        defer { model.started = false }
        model.audioStartupGeneration = 2
        model.audioOutput.registerPendingVoiceBuffer()
        let selection = VirtualAudioSelectionRecoveryPolicy.resolve(selectedUID: "",
            rememberedUID: "", availableDevices: [], hasHistoricalConfiguration: false)
        model.finishAudioStartup(generation: 1, configurationGeneration: 1, configured: false, selection: selection, devices: [])
        // Wait for the actual production cleanup queue; no live HAL device is allocated.
        await withCheckedContinuation { continuation in
            model.audioPreparationQueue.async { continuation.resume() }
        }
        #expect(model.audioOutput.pendingVoiceBufferCountForDiagnostics == 1)
    }
    @Test func currentRecorderDeliversOnceAndDoesNotRetainStoppedMonitor() throws {
        var pending: [() -> Void] = []
        var captures = 0
        var monitor: ShortcutCaptureMonitor? = ShortcutCaptureMonitor(onCapture: { _ in captures += 1 },
            accessibilityTrusted: { true }, modifierIsPressed: { _ in false },
            dispatchCallback: { pending.append($0) })
        weak let weakMonitor = monitor
        monitor?.resetCaptureState()
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true))
        #expect(monitor?.handle(type: .keyDown, event: key) == true)
        pending.removeFirst()()
        #expect(captures == 1)
        monitor?.resetCaptureState()
        #expect(monitor?.handle(type: .keyDown, event: key) == true)
        monitor = nil
        #expect(weakMonitor == nil)
        pending.removeFirst()()
        #expect(captures == 1)
    }

    @Test func stoppedModifierRecorderDiscardsQueuedCapture() throws {
        var pending: [() -> Void] = []
        var captures = 0
        let monitor = ShortcutCaptureMonitor(onCapture: { _ in captures += 1 },
            accessibilityTrusted: { true }, modifierIsPressed: { _ in false },
            dispatchCallback: { pending.append($0) })
        monitor.resetCaptureState()
        let key = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true))
        key.type = .flagsChanged
        key.flags = .maskCommand
        #expect(monitor.handle(type: .flagsChanged, event: key))
        key.flags = []
        #expect(monitor.handle(type: .flagsChanged, event: key))
        #expect(pending.count == 1)
        monitor.stop()
        pending.removeFirst()()
        #expect(captures == 0)
    }

    @Test func startupUsesSelectionMadeWhileEnumerationWasPending() throws {
        let name = "startup-selection-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: values)
        settings.selectedAudioDeviceUID = "original"
        let model = BridgeAppModel(settings: settings)
        model.started = true
        defer { model.started = false }
        model.audioStartupGeneration = 2
        // Represents the main-actor handoff after a slow background enumeration.
        settings.selectedAudioDeviceUID = "user-selected"
        var requests: [String] = []
        model.prepareAudioStartup(generation: 1, devices: [], configureOutput: { uid, _ in requests.append(uid) })
        #expect(requests.isEmpty)
        model.prepareAudioStartup(generation: 2, devices: [], configureOutput: { uid, _ in requests.append(uid) })
        #expect(requests == ["user-selected"])
        #expect(settings.selectedAudioDeviceUID == "user-selected")
        #expect(model.audioOutput.pendingVoiceBufferCountForDiagnostics == 0)
    }

    @Test(arguments: [false, true])
    func unavailableNativeFilterCannotDuplicateMappedActions(seized: Bool) throws {
        let name = "mapping-filter-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: values)
        settings.customMappingEnabled = true
        settings.setAction(.commandQuit, for: .up)
        var actions = 0
        let profile = UUID()
        let monitor = HIDRemoteMonitor(settings: settings, profileID: profile,
            runtimePermissions: { true }, actionPerformer: { _, _, _ in actions += 1; return true },
            diagnosticLogger: { _ in })
        monitor.connectSimulatedDevice(fingerprint: "test", profileID: profile, isSeized: seized)
        let usage = RemoteButton.up.hidUsage
        monitor.handleSimulatedReport(reportID: 1, data: Data([UInt8(usage & 255), UInt8(usage >> 8)]))
        monitor.handleSimulatedReport(reportID: 1, data: Data([0, 0]))
        #expect(actions == (seized ? 1 : 0))
        monitor.disconnectSimulatedDevice()
    }

    @Test(arguments: [false, true])
    func lostFilterCancelsDelayedActions(longPress: Bool) throws {
        let name = "mapping-filter-lost-" + UUID().uuidString
        let values = try #require(UserDefaults(suiteName: name))
        defer { values.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: values)
        settings.customMappingEnabled = true
        if longPress { settings.setAction(.commandQuit, for: .up, trigger: .longPress) }
        let scheduler = OperationScheduler()
        var filtering = true
        var actions = 0
        let profile = UUID()
        let monitor = HIDRemoteMonitor(settings: settings, profileID: profile,
            scheduler: scheduler, runtimePermissions: { true }, nativeSuppressionAvailable: { filtering },
            actionPerformer: { _, _, _ in actions += 1; return true },
            diagnosticLogger: { _ in })
        monitor.connectSimulatedDevice(fingerprint: "test", profileID: profile, isSeized: false)
        let usage = RemoteButton.up.hidUsage
        monitor.handleSimulatedReport(reportID: 1, data: Data([UInt8(usage & 255), UInt8(usage >> 8)]))
        let beforeLoss = actions
        #expect(beforeLoss == (longPress ? 0 : 1))
        filtering = false
        scheduler.fire(after: longPress ? HIDRemoteTiming.longPressMilliseconds : HIDRemoteTiming.repeatStartMilliseconds)
        #expect(actions == beforeLoss)
        monitor.disconnectSimulatedDevice()
    }

}


private final class OperationScheduler: HIDRemoteScheduling {
    final class Task: HIDRemoteScheduledTask {
        let delay: UInt64
        let action: () -> Void
        var cancelled = false
        init(delay: UInt64, action: @escaping () -> Void) { self.delay = delay; self.action = action }
        func cancel() { cancelled = true }
    }
    private var tasks: [Task] = []
    func schedule(afterMilliseconds: UInt64, repeatingEveryMilliseconds: UInt64?,
        _ action: @escaping () -> Void) -> HIDRemoteScheduledTask {
        let task = Task(delay: afterMilliseconds, action: action)
        tasks.append(task)
        return task
    }
    func fire(after delay: UInt64) {
        for task in tasks where task.delay == delay && !task.cancelled { task.action() }
    }
}

import AppKit
import Foundation
import Testing
@testable import VoiceInputBuddy
@testable import AppleRemotePacketLogger

@Suite("Input lifecycle regressions")
@MainActor
struct InputLifecycleRegressionTests {
    private final class Probe {}
    private func defaults() -> (UserDefaults, String) {
        let name = "input-lifecycle-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func failedFnReleaseDoesNotReportCleanupCompleteOrReenter() {
        var operations: [() -> Void] = []
        var allowRelease = false
        var callbacks = 0
        let session = VoiceFnTapSessionController(
            startDelay: 0, tapDuration: 0,
            schedule: { _, operation in
                operations.append(operation)
                return VoiceFnTapScheduledTask(cancellation: {})
            },
            setFunctionKeyPressed: { pressed in pressed || allowRelease },
            enqueueAudio: { _ in }, drainAudio: { _, completion in completion() },
            onFailure: { _ in }
        )
        session.setEnabled(true)
        #expect(session.startVoice())
        operations.removeFirst()()
        operations.removeFirst()()
        #expect(session.requiresCleanupBeforeMapping)
        session.setEnabled(false) { callbacks += 1 }
        #expect(callbacks == 0)
        allowRelease = true
        session.suspend()
        #expect(callbacks == 1)
        #expect(!session.requiresCleanupBeforeMapping)
    }

    @Test func mixedReportDeliversReleaseDespiteRejectedNewPress() {
        let (values, name) = defaults()
        defer { values.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: values)
        settings.customMappingEnabled = true
        settings.configuredActionOverride = { _, _, trigger in
            ConfiguredButtonAction(action: trigger == .singleClick ? .combinationAction : .disabled, shortcut: nil)
        }
        let profile = UUID()
        let monitor = HIDRemoteMonitor(settings: settings, profileID: profile,
            runtimePermissions: { true }, actionPerformer: { _, _, _ in false }, diagnosticLogger: { _ in })
        var releases: [RemoteButton] = []
        monitor.onRuntimeButton = { _, button, edge in
            if edge == .release { releases.append(button) }
            return false
        }
        monitor.connectSimulatedDevice(fingerprint: "test", profileID: profile)
        func report(_ button: RemoteButton) {
            let usage = button.hidUsage
            monitor.handleSimulatedReport(reportID: 1, data: Data([UInt8(usage & 255), UInt8(usage >> 8)]))
        }
        report(.up)
        report(.right)
        #expect(releases == [.up])
        monitor.disconnectSimulatedDevice()
    }

    @Test func stoppedMonitorDoesNotDispatchRemainingPressesInSameReport() {
        let (values, name) = defaults()
        defer { values.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: values)
        settings.customMappingEnabled = true
        settings.configuredActionOverride = { _, _, trigger in
            ConfiguredButtonAction(action: trigger == .singleClick ? .arrowUp : .disabled, shortcut: nil)
        }
        var allowed = true
        let profile = UUID()
        let monitor = HIDRemoteMonitor(settings: settings, profileID: profile,
            runtimePermissions: { allowed }, actionPerformer: { _, _, _ in allowed = false; return false },
            diagnosticLogger: { _ in })
        var presses: [RemoteButton] = []
        monitor.onRuntimeButton = { _, button, edge in
            if edge == .press { presses.append(button) }
            return false
        }
        monitor.connectSimulatedDevice(fingerprint: "test", profileID: profile)
        let usages = [RemoteButton.up.hidUsage, RemoteButton.right.hidUsage].sorted()
        let bytes = usages.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] }
        monitor.handleSimulatedReport(reportID: 1, data: Data(bytes))
        #expect(presses.count == 1)
    }

    @Test func physicalKeyUpIsNeverConsumedAfterItsDownPassed() throws {
        let filter = KeyboardEventSuppressor()
        let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 50, keyDown: true))
        let up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 50, keyDown: false))
        filter.arm(nativeEvents: [.keyboard(keyCode: 50)], edge: .down)
        #expect(filter.handle(type: .keyDown, event: down))
        filter.arm(nativeEvents: [.keyboard(keyCode: 50)], edge: .up)
        #expect(!filter.handle(type: .keyDown, event: down))
        #expect(!filter.handle(type: .keyUp, event: up))
    }

    @Test func unpairedReleaseAndExpiredHoldPass() throws {
        var now = 0.0
        let filter = KeyboardEventSuppressor(uptime: { now })
        let up = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 50, keyDown: false))
        filter.arm(nativeEvents: [.keyboard(keyCode: 50)], edge: .up)
        #expect(!filter.handle(type: .keyUp, event: up))
        let down = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 50, keyDown: true))
        filter.arm(nativeEvents: [.keyboard(keyCode: 50)], edge: .down)
        #expect(filter.handle(type: .keyDown, event: down))
        now = 31
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        #expect(!filter.handle(type: .keyDown, event: down))
    }

    @Test func restartWizardClearsPriorValidationHistory() throws {
        let (values, name) = defaults()
        defer { values.removePersistentDomain(forName: name) }
        let binding = VoiceToolUserBinding(tool: .weixin, shortcut: .function,
            gestureMode: .hold, source: .manuallyConfirmed, validationState: .verified)
        values.set(try JSONEncoder().encode(binding), forKey: "onboarding.verifiedVoiceBinding")
        let settings = AppSettings(defaults: values)
        #expect(settings.verifiedVoiceToolBinding != nil)
        settings.completeOnboarding()
        settings.recordFirstUseEvent(.completed, step: .audio)
        #expect(settings.hasHistoricalAudioConfiguration)
        settings.restartOnboarding()
        #expect(!settings.isOnboardingComplete)
        #expect(settings.firstUseEvents.isEmpty)
        #expect(settings.verifiedVoiceToolBinding == nil)
        #expect(!settings.hasHistoricalAudioConfiguration)
    }

    @Test func recorderIgnoresReleaseOfModifierHeldBeforeOpening() throws {
        var captured: [CustomKeyboardShortcut] = []
        let recorder = ShortcutCaptureMonitor(onCapture: { captured.append($0) },
            accessibilityTrusted: { true }, modifierIsPressed: { $0 == 55 }, dispatchCallback: { $0() })
        recorder.resetCaptureState()
        let command = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: true))
        command.type = .flagsChanged
        command.flags = []
        #expect(recorder.handle(type: .flagsChanged, event: command))
        #expect(captured.isEmpty)
        command.flags = .maskCommand
        #expect(recorder.handle(type: .flagsChanged, event: command))
        #expect(captured.isEmpty)
        let x = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 7, keyDown: true))
        x.flags = .maskCommand
        #expect(recorder.handle(type: .keyDown, event: x))
        #expect(captured.count == 1)
        #expect(captured.first?.keyCode == 7)
    }

    @Test func mediaReleasePassesAfterFreshMediaDown() throws {
        let filter = KeyboardEventSuppressor()
        func event(_ state: Int) throws -> CGEvent {
            let ns = try #require(NSEvent.otherEvent(with: .systemDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: state << 8, data2: -1))
            return try #require(ns.cgEvent)
        }
        let down = try event(0xA), up = try event(0xB)
        let type = CGEventType(rawValue: 14)!
        filter.arm(nativeEvents: [.systemKey(type: 0)], edge: .down)
        #expect(filter.handle(type: type, event: down))
        filter.arm(nativeEvents: [.systemKey(type: 0)], edge: .up)
        #expect(!filter.handle(type: type, event: down))
        #expect(!filter.handle(type: type, event: up))
    }

    @Test func packetLoggerRuleRequiresFreshAdminAuthentication() {
        let rule = AppleRemotePacketLoggerClient.temporaryAuthorizationRule(bundleIdentifier: "com.zfdang.VoiceInputBuddy")
        #expect(AppleRemotePacketLoggerClient.authorizationRuleIsStrongEnough(rule))
        #expect(!AppleRemotePacketLoggerClient.authorizationRuleIsStrongEnough(["class": "allow"] as CFDictionary))
        var weakened = rule as! [String: Any]
        weakened["authenticate-user"] = false
        #expect(!AppleRemotePacketLoggerClient.authorizationRuleIsStrongEnough(weakened as CFDictionary))
    }

    @Test func volumeActionsUseInjectedPoster() {
        var keys: [Int32] = []
        for action: ButtonAction in [.volumeUp, .volumeDown, .volumeMute, .playPause] {
            #expect(KeyboardInjector.send(action, accessibilityTrusted: { true }, systemKeyPoster: { keys.append($0) }))
        }
        #expect(keys == [0, 1, 7, 16])
    }

    @Test func mappingJournalSurvivesRestartAndOfflineRestore() {
        let (values, name) = defaults()
        defer { values.removePersistentDomain(forName: name) }
        let original = HIDUsageMapping(source: RemoteVoiceFunctionMappingPolicy.remoteVoiceKey.source, destination: 99)
        var mappings = [original]
        var online = true
        let provider = { () -> [RemoteVoiceMappingService] in
            guard online else { return [] }
            return [.init(registryID: 123, readMappings: { mappings }, setMappings: { mappings = $0; return true })]
        }
        let first = RemoteVoiceFunctionMapper(serviceProvider: provider, recoveryDefaults: values, bootID: "boot-test")
        #expect(first.apply())
        let restarted = RemoteVoiceFunctionMapper(serviceProvider: provider, recoveryDefaults: values, bootID: "boot-test")
        online = false
        restarted.restore()
        online = true
        let reconnected = RemoteVoiceFunctionMapper(serviceProvider: provider, recoveryDefaults: values, bootID: "boot-test")
        reconnected.restore()
        #expect(mappings == [original])
    }

    @Test func restorationPreservesLaterUserMappings() {
        let foreignVoice = HIDUsageMapping(source: RemoteVoiceFunctionMappingPolicy.remoteVoiceKey.source, destination: 101)
        let foreignPower = HIDUsageMapping(source: RemoteVoiceFunctionMappingPolicy.suppressedRemotePowerKey.source, destination: 102)
        #expect(RemoteVoiceFunctionMappingPolicy.restoring(originalVoiceMapping: nil,
            originalPowerMapping: nil, in: [foreignVoice, foreignPower]) == [foreignVoice, foreignPower])
    }

    @Test func mappingJournalDoesNotCrossSystemBoots() {
        let (values, name) = defaults()
        defer { values.removePersistentDomain(forName: name) }
        let source = RemoteVoiceFunctionMappingPolicy.remoteVoiceKey.source
        var mappings = [HIDUsageMapping(source: source, destination: 99)]
        let provider = { [RemoteVoiceMappingService(registryID: 123,
            readMappings: { mappings }, setMappings: { mappings = $0; return true })] }
        let previous = RemoteVoiceFunctionMapper(serviceProvider: provider, recoveryDefaults: values, bootID: "old")
        #expect(previous.apply())
        mappings = [HIDUsageMapping(source: source, destination: 42)]
        let nextBoot = RemoteVoiceFunctionMapper(serviceProvider: provider, recoveryDefaults: values, bootID: "new")
        #expect(nextBoot.apply())
        nextBoot.restore()
        #expect(mappings == [HIDUsageMapping(source: source, destination: 42)])
    }

    @Test func oneShotAndCancelledTimersReleaseCallbackCaptures() async throws {
        var probe: Probe? = Probe()
        weak let observed = probe
        let handle = DispatchHIDRemoteScheduler().schedule(afterMilliseconds: 0, repeatingEveryMilliseconds: nil) { [retained = probe!] in
            withExtendedLifetime(retained) {}
        }
        probe = nil
        try await Task.sleep(for: .milliseconds(100))
        #expect(observed == nil)
        withExtendedLifetime(handle) {}
        var second: Probe? = Probe()
        weak let secondObserved = second
        var task: HIDRemoteScheduledTask? = DispatchHIDRemoteScheduler().schedule(afterMilliseconds: 1000, repeatingEveryMilliseconds: 10) { [retained = second!] in
            withExtendedLifetime(retained) {}
        }
        second = nil
        withExtendedLifetime(task) {}
        task = nil
        try await Task.sleep(for: .milliseconds(100))
        #expect(secondObserved == nil)
    }
}

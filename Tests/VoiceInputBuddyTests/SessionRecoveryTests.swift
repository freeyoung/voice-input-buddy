import AppKit
import Foundation
import Testing
@testable import VoiceInputBuddy

private final class RecoveryTask: HIDRemoteScheduledTask {
    let due: UInt64
    var action: (() -> Void)?
    init(due: UInt64, action: @escaping () -> Void) { self.due = due; self.action = action }
    func cancel() { action = nil }
}
private final class RecoveryScheduler: HIDRemoteScheduling {
    var clock: UInt64 = 0
    var tasks: [RecoveryTask] = []
    func schedule(afterMilliseconds: UInt64, repeatingEveryMilliseconds: UInt64?, _ action: @escaping () -> Void) -> HIDRemoteScheduledTask {
        let task = RecoveryTask(due: clock + afterMilliseconds, action: action)
        tasks.append(task)
        return task
    }
    func runNext() {
        tasks.sort { $0.due < $1.due }
        while !tasks.isEmpty {
            let task = tasks.removeFirst()
            guard let action = task.action else { continue }
            clock = task.due
            task.action = nil
            action()
            return
        }
    }
    func runAll() { for _ in 0..<20 where tasks.contains(where: { $0.action != nil }) { runNext() } }
}

@Suite("Session recovery")
@MainActor
struct SessionRecoveryTests {
    private func defaults() -> (UserDefaults, String) {
        let name = "session-recovery-" + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func disabledSessionCompletesCleanupWithoutWaitingForLostRemoteStop() {
        let scheduler = RecoveryScheduler()
        var completions = 0
        let session = VoiceFnTapSessionController(startDelay: 0,
            schedule: { delay, action in
                let task = scheduler.schedule(afterMilliseconds: UInt64(delay * 1000), repeatingEveryMilliseconds: nil, action)
                return VoiceFnTapScheduledTask(cancellation: { task.cancel() })
            }, setFunctionKeyPressed: { _ in true }, enqueueAudio: { _ in },
            drainAudio: { _, completion in completion() }, onFailure: { _ in })
        session.setEnabled(true)
        #expect(session.startVoice())
        scheduler.runNext()
        scheduler.runNext()
        session.setEnabled(false) { _ in completions += 1 }
        scheduler.runAll()
        #expect(completions == 1)
        #expect(!session.requiresCleanupBeforeMapping)
        #expect(session.receive([1, 2])) // Quarantine late audio from the old held press.
        session.shutdown()
        #expect(!session.receive([1, 2]))
        #expect(completions == 1)
    }

    @Test func cancelledDrainAnswersExactlyOnceEvenAfterDeadline() async throws {
        let output = VirtualAudioOutput(logger: { _ in })
        output.registerPendingVoiceBuffer()
        var outcomes: [VirtualAudioDrainOutcome] = []
        output.endSessionAfterDraining(maximumDelay: 0.02) { (outcome: VirtualAudioDrainOutcome) in outcomes.append(outcome) }
        output.cancelPendingDrain()
        output.cancelPendingDrain()
        #expect(outcomes == [.forced])
        try await Task.sleep(for: .milliseconds(60))
        #expect(outcomes == [.forced])
    }

    @Test func destroyedOutputAnswersOutstandingDrain() async throws {
        var output: VirtualAudioOutput? = VirtualAudioOutput(logger: { _ in })
        weak let observed = output
        output!.registerPendingVoiceBuffer()
        var outcomes: [VirtualAudioDrainOutcome] = []
        output!.endSessionAfterDraining(maximumDelay: nil) { (outcome: VirtualAudioDrainOutcome) in outcomes.append(outcome) }
        output = nil
        try await Task.sleep(for: .milliseconds(30))
        #expect(observed == nil)
        #expect(outcomes == [.forced])
    }

    @Test func rejectionOnlyClearsItsOwnPendingAudio() {
        let pending = BluetoothPendingAudioStart()
        let owner = UUID()
        pending.begin(for: owner)
        let accepted = pending.audio.appendIfWaiting([1, 2, 3])
        #expect(accepted)
        #expect(!pending.cancel(ifOwnedBy: UUID()))
        #expect(pending.identifier == owner)
        #expect(pending.cancel(ifOwnedBy: owner))
        #expect(pending.identifier == nil)
        let laterAccepted = pending.audio.appendIfWaiting([4])
        let drained = pending.audio.drain()
        #expect(!laterAccepted)
        #expect(drained.isEmpty)
    }

    @Test func acknowledgedWritesSerializeAndDropFailedBacklog() {
        let scheduler = RecoveryScheduler()
        var sent: [Data] = []
        var failures = 0
        let queue = AcknowledgedBluetoothWriteQueue(scheduler: scheduler, send: { sent.append($0) }, onFailure: { failures += 1 })
        #expect(queue.enqueue(Data([1])))
        #expect(queue.enqueue(Data([2])))
        #expect(queue.enqueue(Data([3])))
        #expect(sent == [Data([1])])
        queue.acknowledge(success: true)
        #expect(sent == [Data([1]), Data([2])])
        queue.acknowledge(success: false)
        scheduler.runAll()
        #expect(failures == 1)
        #expect(sent.count == 2)
        #expect(queue.enqueue(Data([4])))
        queue.reset()
        scheduler.runAll()
        #expect(failures == 1)
    }

    @Test func writeTimeoutIsFiniteAndQueueCapacityIsBounded() {
        let scheduler = RecoveryScheduler()
        var failures = 0
        var sent = 0
        let queue = AcknowledgedBluetoothWriteQueue(scheduler: scheduler, send: { _ in sent += 1 }, onFailure: { failures += 1 })
        for _ in 0..<32 { #expect(queue.enqueue(Data([1]))) }
        #expect(!queue.enqueue(Data([2])))
        #expect(sent == 1)
        scheduler.runNext()
        #expect(failures == 1)
        #expect(queue.enqueue(Data([3])))
        queue.acknowledge(success: true)
        scheduler.runAll()
        #expect(failures == 1)
    }

    @Test func bootFallbackIsStableAndNeverUsesOneCrossBootSentinel() {
        #expect(RemoteVoiceFunctionMapper.bootIdentity(uuid: "uuid", bootTime: nil) == "uuid")
        let first = RemoteVoiceFunctionMapper.bootIdentity(uuid: nil, bootTime: (100, 12))
        #expect(first == RemoteVoiceFunctionMapper.bootIdentity(uuid: nil, bootTime: (100, 12)))
        #expect(first != RemoteVoiceFunctionMapper.bootIdentity(uuid: nil, bootTime: (200, 12)))
        #expect(RemoteVoiceFunctionMapper.bootIdentity(uuid: nil, bootTime: nil) == nil)
    }

    @Test func recoveryJournalIsAtomicAndFailurePreventsSystemWrite() throws {
        let (values, name) = defaults()
        defer { values.removePersistentDomain(forName: name) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let original = HIDUsageMapping(source: RemoteVoiceFunctionMappingPolicy.remoteVoiceKey.source, destination: 99)
        var mappings = [original]
        var writes = 0
        let services = { [RemoteVoiceMappingService(registryID: 1, readMappings: { mappings }, setMappings: { mappings = $0; writes += 1; return true })] }
        let first = RemoteVoiceFunctionMapper(serviceProvider: services, recoveryDefaults: values, bootID: "boot", recoveryJournalURL: url)
        #expect(first.apply())
        #expect(FileManager.default.fileExists(atPath: url.path))
        values.removePersistentDomain(forName: name)
        let restarted = RemoteVoiceFunctionMapper(serviceProvider: services, recoveryDefaults: values, bootID: "boot", recoveryJournalURL: url)
        restarted.restore()
        #expect(mappings == [original])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try Data([0]).write(to: directory.appendingPathComponent("file"))
        let invalid = directory.appendingPathComponent("file/journal.json")
        let failing = RemoteVoiceFunctionMapper(serviceProvider: services, recoveryDefaults: values, bootID: "boot", recoveryJournalURL: invalid)
        let before = writes
        #expect(!failing.apply())
        #expect(writes == before)
        let unknownBoot = RemoteVoiceFunctionMapper(serviceProvider: services, recoveryDefaults: values, bootID: nil, recoveryJournalURL: url)
        #expect(!unknownBoot.apply())
        #expect(writes == before)
    }

    @Test func partialImportPreservesApplicationLibraryButReplacesMappingOverrides() throws {
        let (values, name) = defaults()
        defer { values.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: values)
        let profile = CustomApplicationProfile(displayName: "Example", bundleIdentifier: "example.test", applicationPath: "/Applications/Example.app")
        _ = settings.addCustomApplicationProfile(profile)
        let binding = UnifiedButtonBinding(remoteProfileID: nil, button: .left, trigger: .singleClick,
            configured: .init(action: .arrowLeft, shortcut: nil))
        settings.unifiedBaseBindings = [binding]
        var object = try #require(JSONSerialization.jsonObject(with: settings.exportedConfigurationData()) as? [String: Any])
        object.removeValue(forKey: "customApplicationProfiles")
        object.removeValue(forKey: "unifiedBaseBindings")
        try settings.importConfiguration(from: JSONSerialization.data(withJSONObject: object))
        #expect(settings.customApplicationProfiles == [profile])
        #expect(settings.unifiedBaseBindings.isEmpty)
        object["customApplicationProfiles"] = []
        object["unifiedBaseBindings"] = []
        try settings.importConfiguration(from: JSONSerialization.data(withJSONObject: object))
        #expect(settings.customApplicationProfiles.isEmpty)
        #expect(settings.unifiedBaseBindings.isEmpty)
    }



    @Test func environmentDiagnosticsStillCheckPermissions() {
        let context = FirstUseDiagnosticContext(step: .permissions, capabilities: .init(), hasSelectedAudioUID: false)
        #expect(context.failureReason == .bluetoothPermissionDenied)
    }


}

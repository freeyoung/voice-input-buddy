import Foundation
import Testing
import AppleRemoteAudioCore
@testable import VoiceInputBuddy

private final class ReviewTask: HIDRemoteScheduledTask {
    let due: UInt64
    var action: (() -> Void)?
    init(_ due: UInt64, _ action: @escaping () -> Void) { self.due = due; self.action = action }
    func cancel() { action = nil }
}
private final class ReviewClock: HIDRemoteScheduling {
    var now: UInt64 = 0
    var tasks: [ReviewTask] = []
    func schedule(afterMilliseconds: UInt64, repeatingEveryMilliseconds: UInt64?, _ action: @escaping () -> Void) -> HIDRemoteScheduledTask {
        let task = ReviewTask(now + afterMilliseconds, action)
        tasks.append(task)
        return task
    }
    func scheduleSeconds(_ delay: TimeInterval, _ action: @escaping () -> Void) -> VoiceFnTapScheduledTask {
        let task = schedule(afterMilliseconds: UInt64(delay * 1000), repeatingEveryMilliseconds: nil, action)
        return VoiceFnTapScheduledTask { task.cancel() }
    }
    func advance(to end: UInt64) {
        for _ in 0..<100 {
            guard let task = tasks.filter({ $0.action != nil && $0.due <= end }).min(by: { $0.due < $1.due }) else { break }
            now = task.due
            let action = task.action
            task.action = nil
            action?()
        }
        now = end
    }
}
private final class ReviewLoginController: LoginItemControlling {
    var status: LoginItemRegistrationStatus = .notRegistered
    var fail = true
    func register() throws {
        if fail { throw NSError(domain: "test", code: 1) }
        status = .enabled
    }
    func unregister() throws { status = .notRegistered }
    func openLoginItemsSettings() {}
}

@Suite("Review lifecycle recovery")
@MainActor
struct ReviewLifecycleTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "review-" + UUID().uuidString)! }

    @Test func releaseRetriesWithoutAnotherVoiceEventAndOnlyThenCompletes() {
        let clock = ReviewClock()
        var canRelease = false
        var completions = 0
        let session = VoiceFnTapSessionController(startDelay: 0, tapDuration: 0.1,
            schedule: clock.scheduleSeconds,
            setFunctionKeyPressed: { down in down || canRelease }, enqueueAudio: { _ in },
            drainAudio: { _, done in done() }, onFailure: { _ in })
        session.setEnabled(true)
        #expect(session.startVoice())
        clock.advance(to: 100)
        session.setEnabled(false) { completions += 1 }
        #expect(completions == 0)
        #expect(session.requiresCleanupBeforeMapping)
        canRelease = true
        clock.advance(to: 1200)
        #expect(completions == 1)
        #expect(!session.requiresCleanupBeforeMapping)
        clock.advance(to: 4000)
        #expect(completions == 1)
    }

    @Test func destroyingSessionReleasesHeldKeyAndCancelsDelayedTap() {
        let clock = ReviewClock()
        var events: [Bool] = []
        var session: VoiceFnTapSessionController? = VoiceFnTapSessionController(startDelay: 0,
            schedule: clock.scheduleSeconds,
            setFunctionKeyPressed: { events.append($0); return true }, enqueueAudio: { _ in },
            drainAudio: { _, done in done() }, onFailure: { _ in })
        weak let observed = session
        session!.setEnabled(true)
        #expect(session!.startVoice())
        clock.advance(to: 0)
        #expect(events == [true])
        session = nil
        #expect(observed == nil)
        #expect(events == [true, false])
        clock.advance(to: 4000)
        #expect(events == [true, false])
    }

    @Test func missingButtonReleaseDoesNotLatchForever() {
        let clock = ReviewClock()
        let prefs = defaults()
        let monitor = HIDRemoteMonitor(settings: AppSettings(defaults: prefs), scheduler: clock,
            runtimePermissions: { true }, diagnosticLogger: { _ in })
        #expect(monitor.shouldAcceptRawPress(button: .power, action: .commandCopy))
        #expect(!monitor.shouldAcceptRawPress(button: .power, action: .commandCopy))
        clock.advance(to: 7999)
        #expect(!monitor.shouldAcceptRawPress(button: .power, action: .commandCopy))
        clock.advance(to: 8000)
        #expect(monitor.shouldAcceptRawPress(button: .power, action: .commandCopy))
        monitor.stop()
    }

    @Test func foregroundRefreshPreservesLoginFailureUntilRetry() {
        let controller = ReviewLoginController()
        let service = LoginItemService(controller: controller)
        service.setEnabled(true)
        #expect(service.didFailToUpdate)
        service.refresh()
        #expect(service.didFailToUpdate)
        controller.fail = false
        service.setEnabled(true)
        #expect(service.isEnabled)
        #expect(!service.didFailToUpdate)
    }

    @Test func abandonedUpdateCheckExpiresButCompletedResultDoesNot() {
        let clock = ReviewClock()
        let store = UpdateInformationStore(userDefaults: defaults(), checkingTimeout: 1, schedule: clock.scheduleSeconds)
        store.beginChecking()
        clock.advance(to: 1000)
        #expect(store.state == .unavailable)
        store.beginChecking()
        store.setAvailable(displayVersion: "v26-10-12.073", buildVersion: "73", fallbackDescription: nil)
        clock.advance(to: 3000)
        guard case .available = store.state else { Issue.record("Deadline replaced completed result"); return }
        store.beginChecking()
        store.setUpToDate()
        clock.advance(to: 5000)
        #expect(store.state == .upToDate)
    }

    @Test func sparkleLaunchAloneDoesNotSkipFirstUseWizard() {
        let prefs = defaults()
        let settings = AppSettings(defaults: prefs)
        _ = settings.recordLaunchAndDetectCompletedUpdate(currentBuild: "73", sparkleHadLaunchedBefore: true)
        #expect(!settings.isOnboardingComplete)
    }

    @Test func configuredLegacyInstallStillMigratesWithoutRepeatingWizard() {
        let prefs = defaults()
        prefs.set(10.0, forKey: "gainDB")
        let settings = AppSettings(defaults: prefs)
        _ = settings.recordLaunchAndDetectCompletedUpdate(currentBuild: "73", sparkleHadLaunchedBefore: false)
        #expect(settings.isOnboardingComplete)
    }

    @Test func directTypingRejectsProtectedFieldsButAllowsSearch() {
        func coordinator(protected: Bool, text: String) -> VoiceInputDestinationCoordinator {
            VoiceInputDestinationCoordinator(snapshot: {
                VoiceInputDestinationSnapshot(bundleIdentifier: "test", role: "AXTextField", subrole: "",
                    enabled: true, editable: true, protectedContent: protected, semanticText: text)
            })
        }
        if case .cancelled(.targetChanged) = coordinator(protected: true, text: "").waitUntilReady(completion: { _ in }) {} else { Issue.record("Protected destination accepted") }
        if case .cancelled(.targetChanged) = coordinator(protected: false, text: "Password").waitUntilReady(completion: { _ in }) {} else { Issue.record("Password destination accepted") }
        if case .immediate = coordinator(protected: false, text: "Search").waitUntilReady(completion: { _ in }) {} else { Issue.record("Explicit search typing rejected") }
    }

    private func record(_ payload: [UInt8], boundary: UInt16 = 2) -> Data {
        let handle = UInt16(1) | boundary << 12
        let acl: [UInt8] = [UInt8(handle & 255), UInt8(handle >> 8), UInt8(payload.count & 255), UInt8(payload.count >> 8)] + payload
        let length = UInt32(9 + acl.count)
        return Data([UInt8(length >> 24), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)] + Array(repeating: 0, count: 8) + [3] + acl)
    }

    @Test func malformedPacketFloodRemainsBoundedAndResynchronizes() {
        let parser = AppleRemotePklgVoiceExtractor()
        #expect(parser.ingest(Data(repeating: 255, count: 2 * 1024 * 1024)).isEmpty)
        #expect(parser.bufferedByteCount <= 3)
        let payload: [UInt8] = [10, 0, 4, 0, 0x1B, 0x33, 0, 0, 0, 1, 2, 2, 0xB8, 0]
        #expect(parser.ingest(record(payload)).count == 1)
        #expect(parser.bufferedByteCount == 0)
    }

    @Test func aclContinuationOverflowDiscardsAssemblyAndValidFragmentsStillWork() {
        let parser = AppleRemotePklgVoiceExtractor()
        #expect(parser.ingest(record([1, 0, 4, 0])).isEmpty)
        #expect(parser.pendingACLByteCount == 4)
        #expect(parser.ingest(record(Array(repeating: 0, count: 64), boundary: 1)).isEmpty)
        #expect(parser.pendingACLByteCount == 0)
        let payload: [UInt8] = [10, 0, 4, 0, 0x1B, 0x33, 0, 0, 0, 1, 2, 2, 0xB8, 0]
        #expect(parser.ingest(record(Array(payload.prefix(8)))).isEmpty)
        #expect(parser.ingest(record(Array(payload.dropFirst(8)), boundary: 1)).count == 1)
        #expect(parser.pendingACLByteCount == 0)
    }
}

import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Voice destination asynchronous boundaries")
struct DestinationCoordinationTests {
    private func field(_ app: String = "editor", editable: Bool = true, identity: String = "old") -> VoiceInputDestinationSnapshot {
        VoiceInputDestinationSnapshot(bundleIdentifier: app, role: editable ? "AXTextArea" : "AXButton",
            subrole: "", enabled: true, editable: editable, protectedContent: false,
            semanticText: "Composer", focusIdentity: identity)
    }

    @Test func applicationSwitchWaitsForEditableDestinationAndCompletesOnce() {
        let clock = ControlledTestScheduler()
        var current = field()
        var results: [VoiceInputDestinationWaitResult] = []
        let coordinator = VoiceInputDestinationCoordinator(schedule: clock.voiceSchedule, snapshot: { current })
        coordinator.beginTargetSwitch(intent: .application(bundleIdentifier: "target"))
        _ = coordinator.waitUntilReady { results.append($0) }
        current = field("target", editable: false)
        clock.fire(afterMilliseconds: 50)
        #expect(results.isEmpty)
        current = field("target", identity: "new")
        clock.fire(afterMilliseconds: 50)
        #expect(results == [.ready])
        for task in clock.tasks { task.fire(includingCancelled: true) }
        #expect(results == [.ready])
    }

    @Test func leavingObservedTargetCancelsInsteadOfAdoptingAnotherApp() {
        let clock = ControlledTestScheduler()
        var current = field()
        var results: [VoiceInputDestinationWaitResult] = []
        let coordinator = VoiceInputDestinationCoordinator(schedule: clock.voiceSchedule, snapshot: { current })
        coordinator.beginTargetSwitch(intent: .application(bundleIdentifier: "target"))
        _ = coordinator.waitUntilReady { results.append($0) }
        current = field("target", editable: false)
        clock.fire(afterMilliseconds: 50)
        current = field("unrelated", identity: "new")
        clock.fire(afterMilliseconds: 50)
        #expect(results == [.cancelled(.targetChanged)])
    }

    @Test func shortcutCannotReuseOldEditableFieldUntilFocusChanges() {
        let clock = ControlledTestScheduler()
        var current = field()
        var results: [VoiceInputDestinationWaitResult] = []
        let coordinator = VoiceInputDestinationCoordinator(schedule: clock.voiceSchedule, snapshot: { current })
        coordinator.beginTargetSwitch(intent: .shortcut)
        _ = coordinator.waitUntilReady { results.append($0) }
        clock.fire(afterMilliseconds: 50)
        #expect(results.isEmpty)
        current = field(identity: "new")
        clock.fire(afterMilliseconds: 50)
        #expect(results == [.ready])
    }

    @Test func oldTimeoutAndOldWaiterCancellationCannotCancelNewRequest() throws {
        let clock = ControlledTestScheduler()
        var current = field()
        var oldResults: [VoiceInputDestinationWaitResult] = []
        var newResults: [VoiceInputDestinationWaitResult] = []
        let coordinator = VoiceInputDestinationCoordinator(schedule: clock.voiceSchedule, snapshot: { current })
        coordinator.beginTargetSwitch(intent: .application(bundleIdentifier: "first"))
        let oldWait = coordinator.waitUntilReady { oldResults.append($0) }
        guard case let .waiting(oldToken) = oldWait else { Issue.record("Expected pending request"); return }
        let timeout = try #require(clock.tasks.first(where: { $0.delay == 5_000 }))
        coordinator.beginTargetSwitch(intent: .application(bundleIdentifier: "second"))
        _ = coordinator.waitUntilReady { newResults.append($0) }
        #expect(oldResults == [.cancelled(.superseded)])
        timeout.fire(includingCancelled: true)
        oldToken.cancel()
        #expect(newResults.isEmpty)
        current = field("second", identity: "new")
        clock.fire(afterMilliseconds: 50)
        #expect(newResults == [.ready])
        #expect(clock.activeCount == 0)
    }

    @Test func timeoutDeliversOnceAndLateFocusCompletionIsIgnored() {
        let clock = ControlledTestScheduler()
        var results: [VoiceInputDestinationWaitResult] = []
        let coordinator = VoiceInputDestinationCoordinator(schedule: clock.voiceSchedule, snapshot: { field() })
        let request = coordinator.beginTargetSwitch(intent: .focusInput)
        _ = coordinator.waitUntilReady { results.append($0) }
        clock.fire(afterMilliseconds: 5_000)
        coordinator.completeFocusOperation(requestID: request, succeeded: true)
        coordinator.shutdown()
        for task in clock.tasks { task.fire(includingCancelled: true) }
        #expect(results == [.cancelled(.timedOut)])
        #expect(clock.activeCount == 0)
    }
}

import Foundation
@testable import VoiceInputBuddy

/// Keeps callbacks so tests can deliver a signal already dequeued before cancellation.
/// No timer, run loop, permission check or wall-clock sleep is used.
final class ControlledTestScheduler: HIDRemoteScheduling {
    final class Task: HIDRemoteScheduledTask {
        let delay: UInt64
        let action: () -> Void
        private(set) var cancelled = false
        init(delay: UInt64, action: @escaping () -> Void) { self.delay = delay; self.action = action }
        func cancel() { cancelled = true }
        func fire(includingCancelled: Bool = false) {
            if includingCancelled || !cancelled { action() }
        }
    }
    private(set) var tasks: [Task] = []
    var activeCount: Int { tasks.filter { !$0.cancelled }.count }
    func schedule(afterMilliseconds: UInt64, repeatingEveryMilliseconds: UInt64?,
        _ action: @escaping () -> Void) -> HIDRemoteScheduledTask {
        let task = Task(delay: afterMilliseconds, action: action)
        tasks.append(task)
        return task
    }
    func voiceSchedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> VoiceFnTapScheduledTask {
        let task = schedule(afterMilliseconds: UInt64((delay * 1_000).rounded()),
            repeatingEveryMilliseconds: nil, action)
        return VoiceFnTapScheduledTask { task.cancel() }
    }
    func fire(afterMilliseconds delay: UInt64) {
        for task in tasks.filter({ $0.delay == delay && !$0.cancelled }) { task.fire() }
    }
}

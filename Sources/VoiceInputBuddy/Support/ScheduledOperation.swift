import Foundation

struct ScheduledOperation {
    private let cancellation: () -> Void

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation()
    }

    static func mainQueue(
        after delay: TimeInterval,
        operation: @escaping () -> Void
    ) -> ScheduledOperation {
        scheduled(after: delay, enqueue: { delay, item in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }, operation: operation)
    }

    static func scheduled(after delay: TimeInterval,
                          enqueue: (TimeInterval, DispatchWorkItem) -> Void,
                          operation: @escaping () -> Void) -> ScheduledOperation {
        let pending = PendingOperation(operation)
        let item = DispatchWorkItem { pending.perform() }
        enqueue(delay, item)
        return ScheduledOperation {
            pending.cancel()
            item.cancel()
        }
    }
}

/// Owns the callback without capturing its DispatchWorkItem. Clearing it on both
/// terminal paths also releases captured objects when the task handle is retained.
private final class PendingOperation {
    private let lock = NSLock()
    private var operation: (() -> Void)?

    init(_ operation: @escaping () -> Void) {
        self.operation = operation
    }

    func perform() {
        lock.lock()
        let operation = self.operation
        self.operation = nil
        lock.unlock()
        operation?()
    }

    func cancel() {
        lock.lock()
        let cancelledOperation = operation
        operation = nil
        lock.unlock()
        withExtendedLifetime(cancelledOperation) {}
    }
}

typealias OperationScheduler = (TimeInterval, @escaping () -> Void) -> ScheduledOperation

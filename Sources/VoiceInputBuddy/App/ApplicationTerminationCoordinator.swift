import Foundation

/// Coalesces repeated quit requests while the Fn release recovery completes.
@MainActor
final class ApplicationTerminationCoordinator {
    private(set) var isTerminating = false
    private var didReply = false

    func request(begin: (@escaping () -> Void) -> Void, reply: @escaping () -> Void) {
        guard !isTerminating else { return }
        isTerminating = true
        begin { [weak self] in
            guard let self, !self.didReply else { return }
            self.didReply = true
            reply()
        }
    }
}

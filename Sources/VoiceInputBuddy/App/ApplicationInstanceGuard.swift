import AppKit
import Darwin
import Foundation

enum ApplicationInstanceLockAcquisition {
    case acquired(ApplicationInstanceLock)
    case alreadyLocked
    case failed(String)
}

final class ApplicationInstanceLock {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        _ = flock(fileDescriptor, LOCK_UN)
        _ = Darwin.close(fileDescriptor)
    }

    static func acquireForLaunch(at lockURL: URL,
        existingInstanceIsRunning: () -> Bool,
        pause: () -> Void = { Thread.sleep(forTimeInterval: 0.15) }
    ) -> ApplicationInstanceLockAcquisition {
        let first = acquire(at: lockURL)
        guard case .alreadyLocked = first, !existingInstanceIsRunning() else { return first }
        // A terminating process may have disappeared from AppKit just before releasing flock.
        for _ in 0..<8 {
            pause()
            let next = acquire(at: lockURL)
            guard case .alreadyLocked = next else { return next }
            if existingInstanceIsRunning() { return next }
        }
        return .alreadyLocked
    }

    static func acquire(at lockURL: URL) -> ApplicationInstanceLockAcquisition {
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            let cocoaError = error as NSError
            return .failed(
                "create_directory domain=\(cocoaError.domain) code=\(cocoaError.code)"
            )
        }

        let descriptor = lockURL.path.withCString { path in
            Darwin.open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            return .failed("open errno=\(errno)")
        }
        _ = fchmod(descriptor, S_IRUSR | S_IWUSR)

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            _ = Darwin.close(descriptor)
            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                return .alreadyLocked
            }
            return .failed("flock errno=\(lockError)")
        }
        return .acquired(ApplicationInstanceLock(fileDescriptor: descriptor))
    }
}

enum ApplicationInstanceGuard {
    static let fallbackBundleIdentifier = "com.zfdang.voice-input-buddy"

    static func existingApplication(
        bundleIdentifier: String,
        currentProcessIdentifier: pid_t = getpid(),
        requiresFinishedLaunch: Bool = false
    ) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first {
                !$0.isTerminated &&
                    $0.processIdentifier != currentProcessIdentifier &&
                    (!requiresFinishedLaunch || $0.isFinishedLaunching)
            }
    }

    static func defaultLockURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("VoiceInputBuddy", isDirectory: true)
            .appendingPathComponent(".app-instance.lock", isDirectory: false)
    }
}

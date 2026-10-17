import AppKit

/// A short pasteboard lease. All entry points and completions run on the main queue.
/// The queue keeps the lease alive until restoration, even if the panel is closed.
final class CommonPhraseClipboardPaste {
    static let shared = CommonPhraseClipboardPaste()
    typealias Validation = (@escaping (String?) -> Void) -> Void
    private static let snapshotQueue = DispatchQueue(label: "voice-input-buddy.clipboard.snapshot", qos: .userInitiated)
    private let modifierFlags: () -> CGEventFlags
    private let uptime: () -> TimeInterval
    private let board: NSPasteboard
    private let readClipboard: (@escaping () -> Void) -> Void
    private let snapshotExecutableURL: URL?
    private let usesSnapshotHelper: Bool
    private let schedule: OperationScheduler
    private let postPaste: () -> Bool
    private var busy = false
    private var snapshotInFlight = false
    private var generation: UInt64 = 0

    init(board: NSPasteboard = .general,
         modifierFlags: @escaping () -> CGEventFlags = { pasteHardwareFlags() },
         uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         snapshotExecutableURL: URL? = Bundle.main.executableURL,
         readClipboard: ((@escaping () -> Void) -> Void)? = nil,
         schedule: @escaping OperationScheduler = ScheduledOperation.mainQueue,
         postPaste: @escaping () -> Bool = {
             guard KeyboardInjector.isAccessibilityTrusted else {
                 AppLogger.shared.write("COMMON_PHRASES PASTE rejected reason=accessibility_required")
                 return false
             }
             guard !SecureInputMonitor.isEnabled() else {
                 AppLogger.shared.write("COMMON_PHRASES PASTE rejected reason=secure_input")
                 return false
             }
             let hardware = pasteHardwareFlags()
             guard permitsPasteShortcut(flags: hardware) else {
                 AppLogger.shared.write("COMMON_PHRASES PASTE rejected reason=modifiers_held flags=\(hardware.rawValue)")
                 return false
             }
             return ShortcutEventSequence.send(keyCode: 9, modifiers: .maskCommand,
                 hardwareFlags: { pasteHardwareFlags() }, eventPoster: ShortcutEventSequence.post)
         }) {
        self.modifierFlags = modifierFlags
        self.uptime = uptime
        self.board = board
        self.snapshotExecutableURL = snapshotExecutableURL
        self.readClipboard = readClipboard ?? { work in Self.snapshotQueue.async { work() } }
        self.usesSnapshotHelper = readClipboard == nil
        self.schedule = schedule
        self.postPaste = postPaste
    }

    // Navigation keys can carry the Fn event flag without an actual Fn key
    // press. Do not let that decoration block or alter Command-V.
    static func normalizedPasteFlags(_ flags: CGEventFlags, fnKeyDown: Bool) -> CGEventFlags {
        fnKeyDown ? flags.union(.maskSecondaryFn) : flags.subtracting(.maskSecondaryFn)
    }

    private static func pasteHardwareFlags() -> CGEventFlags {
        normalizedPasteFlags(CGEventSource.flagsState(.hidSystemState),
            fnKeyDown: CGEventSource.keyState(.hidSystemState, key: 63))
    }

    static func permitsPasteShortcut(flags: CGEventFlags) -> Bool {
        flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty
    }

    func paste(_ text: String, validate: @escaping Validation, canSubmit: @escaping () -> Bool,
               completion: @escaping (String?) -> Void) {
        guard !busy else { completion("paste_failed"); return }
        guard !snapshotInFlight else { completion("clipboard_write_failed"); return }
        busy = true
        generation &+= 1
        let token = generation
        // Selecting a phrase starts on the remote's key-down. HID-system key state
        // can still report Fn until the paired native navigation key-up arrives.
        // Wait before reading or leasing the clipboard; never clear a real held modifier.
        validate { failure in
            guard self.busy, self.generation == token else { return }
            if let failure { self.finish(failure, completion); return }
            self.waitForReleasedModifiers(token: token, deadline: self.uptime() + 0.5, canSubmit: canSubmit) { failure in
                guard self.busy, self.generation == token else { return }
                if let failure { self.finish(failure, completion); return }
                let originalCount = self.board.changeCount
                let name = self.board.name
                self.snapshotInFlight = true
                var waiting = true
                let deadline = self.schedule(2) {
                    guard waiting, self.busy, self.generation == token else { return }
                    waiting = false
                    self.snapshotInFlight = false
                    self.finish("clipboard_write_failed", completion)
                }
                self.readClipboard {
                    // Promised clipboard data may require IPC to an unresponsive app.
                    // Read through a separate instance off-main, before any mutation.
                    let saved = self.usesSnapshotHelper
                        ? Self.readSnapshotInHelper(name: name, executableURL: self.snapshotExecutableURL)
                        : Self.snapshot(NSPasteboard(name: name))
                    let deliver = {
                        guard waiting, self.busy, self.generation == token else { return }
                        self.snapshotInFlight = false
                        waiting = false
                        deadline.cancel()
                        guard let saved, self.board.changeCount == originalCount else {
                            self.finish("clipboard_write_failed", completion); return
                        }
                        self.submit(text, saved: saved, originalCount: originalCount, validate: validate, canSubmit: canSubmit, completion: completion)
                    }
                    if Thread.isMainThread { deliver() }
                    else { DispatchQueue.main.async(execute: deliver) }
                }
            }
        }
    }

    private func waitForReleasedModifiers(token: UInt64, deadline: TimeInterval,
        canSubmit: @escaping () -> Bool, hasWaited: Bool = false,
        completion: @escaping (String?) -> Void
    ) {
        guard busy, generation == token else { return }
        guard canSubmit() else { completion("target_changed"); return }
        let flags = modifierFlags()
        if Self.permitsPasteShortcut(flags: flags) {
            if hasWaited { AppLogger.shared.write("COMMON_PHRASES PASTE modifiers_released") }
            completion(nil)
            return
        }
        let remaining = deadline - uptime()
        guard remaining > 0 else {
            AppLogger.shared.write("COMMON_PHRASES PASTE rejected reason=modifiers_held_after_wait flags=\(flags.rawValue)")
            completion("paste_failed")
            return
        }
        if !hasWaited { AppLogger.shared.write("COMMON_PHRASES PASTE waiting reason=modifiers_held flags=\(flags.rawValue)") }
        _ = schedule(min(0.025, max(0.001, remaining))) {
            self.waitForReleasedModifiers(token: token, deadline: deadline, canSubmit: canSubmit,
                hasWaited: true, completion: completion)
        }
    }

    private func submit(_ text: String, saved: Snapshot, originalCount: Int, validate: @escaping Validation,
                        canSubmit: @escaping () -> Bool, completion: @escaping (String?) -> Void) {
        // Revalidate after the potentially slow snapshot, before exposing the
        // phrase on the pasteboard. No AX IPC is performed while we own it.
        validate { failure in
            guard self.board.changeCount == originalCount else { self.finish("paste_failed", completion); return }
            guard failure == nil, canSubmit() else { self.finish(failure ?? "target_changed", completion); return }
            guard self.board.changeCount == originalCount else { self.finish("paste_failed", completion); return }
            self.board.clearContents()
            let lease = self.board.changeCount
            guard self.board.setString(text, forType: .string) else {
                self.finish(self.restore(saved, lease: lease) ? "clipboard_write_failed" : "clipboard_restore_failed", completion)
                return
            }
            guard canSubmit() else {
                let restored = self.restore(saved, lease: lease)
                self.finish(restored ? "target_changed" : "clipboard_restore_failed", completion)
                return
            }
            guard self.board.changeCount == lease else { self.finish("paste_failed", completion); return }
            let submitted = self.postPaste()
            // CGEventPost has no receiving-app acknowledgement. Allow a bounded
            // read interval without claiming the target committed the text.
            _ = self.schedule(0.75) {
                let restored = self.restore(saved, lease: lease)
                self.finish(restored ? (submitted ? nil : "paste_failed") : "clipboard_restore_failed", completion)
            }
        }
    }

    private func finish(_ failure: String?, _ completion: (String?) -> Void) {
        busy = false
        completion(failure)
    }

    private struct SnapshotValue: Codable {
        let type: String
        let data: Data
    }
    private typealias Snapshot = [[SnapshotValue]]

    // Isolate promised-data IPC in a killable process. A dispatch timeout alone cannot
    // interrupt NSPasteboard reads, and replacing a serial queue would leak workers.
    private static func readSnapshotInHelper(name: NSPasteboard.Name, executableURL: URL?) -> Snapshot? {
        guard let executable = executableURL else { return nil }
        let result = BoundedCommandRunner.run(executableURL: executable,
            arguments: ["--snapshot-pasteboard", name.rawValue], timeout: 1.5,
            outputLimit: 34 * 1_024 * 1_024)
        guard !result.timedOut, result.terminationStatus == 0 else { return nil }
        return try? PropertyListDecoder().decode(Snapshot.self, from: result.standardOutput)
    }

    static func runSnapshotHelperIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard arguments.count == 3, arguments[1] == "--snapshot-pasteboard" else { return false }
        guard let saved = snapshot(NSPasteboard(name: .init(arguments[2]))) else { return true }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(saved) { try? FileHandle.standardOutput.write(contentsOf: data) }
        return true
    }

    private static func snapshot(_ board: NSPasteboard) -> Snapshot? {
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { return nil }
        guard let items = board.pasteboardItems else { return nil }
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { return nil }
        var result: Snapshot = []
        var size = 0
        for item in items {
            var values: [SnapshotValue] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                // Refuse to replace a large/unreadable clipboard instead of saving
                // only some formats and silently destroying the rest.
                guard data.count <= 32 * 1_024 * 1_024 - size else { return nil }
                size += data.count
                values.append(SnapshotValue(type: type.rawValue, data: data))
            }
            result.append(values)
        }
        return result
    }

    private func restore(_ saved: Snapshot, lease: Int) -> Bool {
        guard board.changeCount == lease else { return true }
        var items: [NSPasteboardItem] = []
        for values in saved {
            let item = NSPasteboardItem()
            for value in values {
                guard item.setData(value.data, forType: .init(value.type)) else { return false }
            }
            items.append(item)
        }
        guard board.changeCount == lease else { return true }
        board.clearContents()
        return items.isEmpty || board.writeObjects(items)
    }
}

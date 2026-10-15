import AppKit

/// A short pasteboard lease. All entry points and completions run on the main queue.
/// The queue keeps the lease alive until restoration, even if the panel is closed.
final class CommonPhraseClipboardPaste {
    static let shared = CommonPhraseClipboardPaste()
    typealias Validation = (@escaping (String?) -> Void) -> Void
    private static let snapshotQueue = DispatchQueue(label: "voice-input-buddy.clipboard.snapshot", qos: .userInitiated)
    private let board: NSPasteboard
    private let readClipboard: (@escaping () -> Void) -> Void
    private let schedule: OperationScheduler
    private let postPaste: () -> Bool
    private var busy = false
    private var snapshotInFlight = false
    private var generation: UInt64 = 0

    init(board: NSPasteboard = .general,
         readClipboard: @escaping (@escaping () -> Void) -> Void = { work in snapshotQueue.async { work() } },
         schedule: @escaping OperationScheduler = ScheduledOperation.mainQueue,
         postPaste: @escaping () -> Bool = {
             guard KeyboardInjector.isAccessibilityTrusted, !SecureInputMonitor.isEnabled() else { return false }
             let hardware = CGEventSource.flagsState(.hidSystemState)
             guard hardware.intersection([.maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty else { return false }
             return ShortcutEventSequence.send(keyCode: 9, modifiers: .maskCommand,
                 hardwareFlags: { CGEventSource.flagsState(.hidSystemState) }, eventPoster: ShortcutEventSequence.post)
         }) {
        self.board = board
        self.readClipboard = readClipboard
        self.schedule = schedule
        self.postPaste = postPaste
    }

    func paste(_ text: String, validate: @escaping Validation, canSubmit: @escaping () -> Bool,
               completion: @escaping (String?) -> Void) {
        guard !busy else { completion("paste_failed"); return }
        guard !snapshotInFlight else { completion("clipboard_write_failed"); return }
        busy = true
        generation &+= 1
        let token = generation
        validate { failure in
            guard self.busy, self.generation == token else { return }
            if let failure { self.finish(failure, completion); return }
            let originalCount = self.board.changeCount
            let name = self.board.name
            self.snapshotInFlight = true
            var waiting = true
            let deadline = self.schedule(2) {
                guard waiting, self.busy, self.generation == token else { return }
                waiting = false
                self.finish("clipboard_write_failed", completion)
            }
            self.readClipboard {
                // Promised clipboard data may require IPC to an unresponsive app.
                // Read through a separate instance off-main, before any mutation.
                let saved = Self.snapshot(NSPasteboard(name: name))
                let deliver = {
                    self.snapshotInFlight = false
                    guard waiting, self.busy, self.generation == token else { return }
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

    private typealias Snapshot = [[(type: NSPasteboard.PasteboardType, data: Data)]]

    private static func snapshot(_ board: NSPasteboard) -> Snapshot? {
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { return nil }
        guard let items = board.pasteboardItems else { return nil }
        if #available(macOS 15.4, *), board.accessBehavior == .alwaysDeny { return nil }
        var result: Snapshot = []
        var size = 0
        for item in items {
            var values: [(type: NSPasteboard.PasteboardType, data: Data)] = []
            for type in item.types {
                guard let data = item.data(forType: type) else { return nil }
                // Refuse to replace a large/unreadable clipboard instead of saving
                // only some formats and silently destroying the rest.
                guard data.count <= 32 * 1_024 * 1_024 - size else { return nil }
                size += data.count
                values.append((type, data))
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
            for (type, data) in values {
                guard item.setData(data, forType: type) else { return false }
            }
            items.append(item)
        }
        guard board.changeCount == lease else { return true }
        board.clearContents()
        return items.isEmpty || board.writeObjects(items)
    }
}

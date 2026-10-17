import AppKit
import Testing
@testable import VoiceInputBuddy

@Suite("Common phrase clipboard fallback")
@MainActor
struct CommonPhraseClipboardTests {
    @Test func externalKeyboardFnWithoutNavigationDecorationIsNeverRemoved() {
        let flags = KeyboardHardwareModifierPolicy.normalized(.maskSecondaryFn, fnKeyDown: false)
        #expect(flags.contains(.maskSecondaryFn))
        #expect(!CommonPhraseClipboardPaste.permitsPasteShortcut(flags: flags))
    }

    @Test func navigationReleaseRaceWaitsBeforeReadingOrReplacingClipboard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let clock = ControlledTestScheduler()
        // Exact effective flag value observed during the failed remote-left selections.
        var flags = CGEventFlags(rawValue: 0xA00100)
        var reads = 0, posts = 0, completions = 0
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { flags },
            uptime: { Double(clock.now) / 1_000 }, readClipboard: { reads += 1; $0() },
            schedule: clock.voiceSchedule, postPaste: { posts += 1; return true })
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) {
            #expect($0 == nil); completions += 1
        }
        clock.advance(to: 150)
        #expect(reads == 0 && posts == 0 && completions == 0)
        #expect(board.string(forType: .string) == "original")
        flags = [] // Native navigation key-up clears the transient HID state.
        clock.advance(to: 175)
        #expect(reads == 1 && posts == 1)
        #expect(board.string(forType: .string) == "phrase")
        clock.runAll()
        #expect(completions == 1)
        #expect(board.string(forType: .string) == "original")
    }

    @Test(arguments: [CGEventFlags.maskSecondaryFn, .maskControl, .maskAlternate, .maskShift])
    func trulyHeldModifierTimesOutWithoutTouchingClipboardAndAllowsRetry(held: CGEventFlags) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let clock = ControlledTestScheduler()
        var flags = held
        var reads = 0, posts = 0
        var results: [String?] = []
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { flags },
            uptime: { Double(clock.now) / 1_000 }, readClipboard: { reads += 1; $0() },
            schedule: clock.voiceSchedule, postPaste: { posts += 1; return true })
        writer.paste("blocked", validate: { $0(nil) }, canSubmit: { true }) { results.append($0) }
        clock.advance(to: 500)
        #expect(results == ["paste_failed"])
        #expect(reads == 0 && posts == 0)
        #expect(board.string(forType: .string) == "original")
        flags = []
        writer.paste("retry", validate: { $0(nil) }, canSubmit: { true }) { results.append($0) }
        clock.runAll()
        #expect(reads == 1 && posts == 1)
        #expect(results.count == 2 && results[1] == nil)
        #expect(board.string(forType: .string) == "original")
    }

    @Test func changedTargetDuringModifierWaitCancelsBeforeClipboardAccess() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let clock = ControlledTestScheduler()
        var current = true
        var result: String?
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { .maskSecondaryFn },
            uptime: { Double(clock.now) / 1_000 },
            readClipboard: { _ in Issue.record("Changed target must not trigger clipboard IPC") },
            schedule: clock.voiceSchedule, postPaste: { Issue.record("Changed target must not receive paste"); return true })
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { current }) { result = $0 }
        current = false
        clock.runAll()
        #expect(result == "target_changed")
        #expect(board.string(forType: .string) == "original")
    }

    @Test func consecutivePhrasesDoNotLeaveTabsBeforeTheNextInsertion() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original clipboard", forType: .string)
        let clock = ControlledTestScheduler()
        var editor = "已有文本："
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { $0() },
            schedule: clock.voiceSchedule, postPaste: {
                editor += board.string(forType: .string) ?? ""
                return true
            })
        for body in ["第一条\t", "\t 第二条 \t"] {
            let phrase = CommonPhrase(id: "user-test", text: body,
                label: "标签")
            writer.paste(phrase.insertionText, validate: { $0(nil) }, canSubmit: { true }) {
                #expect($0 == nil)
            }
            clock.runAll()
        }
        #expect(editor == "已有文本：第一条第二条")
        #expect(board.string(forType: .string) == "original clipboard")
    }

    @Test func navigationFnFlagDoesNotBlockOrModifyPaste() {
        let flags = KeyboardHardwareModifierPolicy.normalized([.maskSecondaryFn, .maskNumericPad], fnKeyDown: false)
        #expect(!flags.contains(.maskSecondaryFn))
        #expect(flags.contains(.maskNumericPad))
        #expect(CommonPhraseClipboardPaste.permitsPasteShortcut(flags: flags))
    }

    @Test func physicallyHeldModifiersStillBlockPaste() {
        let fn = KeyboardHardwareModifierPolicy.normalized([], fnKeyDown: true)
        #expect(!CommonPhraseClipboardPaste.permitsPasteShortcut(flags: fn))
        for modifier: CGEventFlags in [.maskControl, .maskAlternate, .maskShift] {
            let flags = KeyboardHardwareModifierPolicy.normalized([modifier, .maskSecondaryFn], fnKeyDown: false)
            #expect(!CommonPhraseClipboardPaste.permitsPasteShortcut(flags: flags))
        }
        #expect(CommonPhraseClipboardPaste.permitsPasteShortcut(flags: .maskCommand))
    }

    @Test func restoresEveryItemAndFormatAfterPaste() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("com.example.binary")
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        first.setString("original", forType: .string)
        first.setData(Data([0, 1, 255]), forType: type)
        second.setString("second item", forType: .string)
        board.writeObjects([first, second])
        let originalTypes = board.pasteboardItems?.first?.types
        let clock = ControlledTestScheduler()
        var posts = 0
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: {
            posts += 1
            #expect(board.string(forType: .string) == "phrase")
            return true
        })
        var completed = false
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) {
            #expect($0 == nil); completed = true
        }
        #expect(posts == 1 && !completed)
        #expect(board.string(forType: .string) == "phrase")
        clock.runAll()
        #expect(completed)
        #expect(board.pasteboardItems?.count == 2)
        #expect(board.pasteboardItems?.first?.types == originalTypes)
        #expect(board.pasteboardItems?.first?.string(forType: .string) == "original")
        #expect(board.pasteboardItems?.first?.data(forType: type) == Data([0, 1, 255]))
        #expect(board.pasteboardItems?.last?.string(forType: .string) == "second item")
    }

    @Test func aNewUserCopyIsNeverRestoredOver() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let clock = ControlledTestScheduler()
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: { true })
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) { #expect($0 == nil) }
        board.clearContents()
        board.setString("new user copy", forType: .string)
        let count = board.changeCount
        clock.runAll()
        #expect(board.string(forType: .string) == "new user copy")
        #expect(board.changeCount == count)
    }

    @Test(arguments: [false, true])
    func validationFailureNeverPostsAndPreservesClipboard(secondCheck: Bool) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { $0() }, postPaste: {
            Issue.record("Invalid target must not receive paste"); return true
        })
        var calls = 0
        var failure: String?
        writer.paste("phrase", validate: { done in
            calls += 1
            done(calls == 1 && secondCheck ? nil : "target_changed")
        }, canSubmit: { true }) { failure = $0 }
        #expect(failure == "target_changed")
        #expect(board.string(forType: .string) == "original")
    }

    @Test func changedClipboardDuringRevalidationCancelsTheKeyEvent() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        var validations: [(String?) -> Void] = []
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { $0() }, postPaste: {
            Issue.record("Must not paste someone else's new clipboard"); return true
        })
        var result: String?
        writer.paste("phrase", validate: { validations.append($0) }, canSubmit: { true }) { result = $0 }
        try #require(validations.count == 1)
        validations[0](nil)
        try #require(validations.count == 2)
        board.clearContents()
        board.setString("new copy", forType: .string)
        validations[1](nil)
        #expect(result == "paste_failed")
        #expect(board.string(forType: .string) == "new copy")
    }

    @Test(arguments: [false, true])
    func cleanupSurvivesOwnerReleaseAndHandlesEmptyClipboard(submitted: Bool) {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        let clock = ControlledTestScheduler()
        var writer: CommonPhraseClipboardPaste? = .init(board: board, modifierFlags: { [] }, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: { submitted })
        var completed = false
        writer?.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) {
            #expect($0 == (submitted ? nil : "paste_failed")); completed = true
        }
        writer = nil
        clock.runAll()
        #expect(completed)
        #expect(board.string(forType: .string) == nil)
    }

    @Test func lateFocusLossAndConcurrentTransactionsDoNotSendMoreKeys() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let clock = ControlledTestScheduler()
        var posts = 0
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: { posts += 1; return true })
        writer.paste("blocked", validate: { $0(nil) }, canSubmit: { false }) { #expect($0 == "target_changed") }
        #expect(posts == 0)
        #expect(board.string(forType: .string) == "original")
        writer.paste("first", validate: { $0(nil) }, canSubmit: { true }) { #expect($0 == nil) }
        writer.paste("second", validate: { $0(nil) }, canSubmit: { true }) { #expect($0 == "paste_failed") }
        #expect(posts == 1)
        clock.runAll()
        #expect(board.string(forType: .string) == "original")
    }

    @Test func anOversizedSnapshotLeavesTheOriginalClipboardUntouched() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let type = NSPasteboard.PasteboardType("com.example.large")
        let original = Data(repeating: 7, count: 32 * 1_024 * 1_024 + 1)
        board.setData(original, forType: type)
        let count = board.changeCount
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { $0() }, postPaste: {
            Issue.record("Must not paste without a complete snapshot"); return true
        })
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) { #expect($0 == "clipboard_write_failed") }
        #expect(board.changeCount == count)
        #expect(board.data(forType: type) == original)
    }

    @Test func aStuckSnapshotAllowsRetryAndCannotCancelANewerSnapshot() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let clock = ControlledTestScheduler()
        var reads: [() -> Void] = []
        var completions = 0
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, readClipboard: { reads.append($0) },
            schedule: clock.voiceSchedule, postPaste: { true })
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) {
            #expect($0 == "clipboard_write_failed"); completions += 1
        }
        #expect(board.string(forType: .string) == "original")
        clock.runAll()
        #expect(completions == 1)
        writer.paste("retry", validate: { $0(nil) }, canSubmit: { true }) { #expect($0 == nil) }
        #expect(reads.count == 2)
        let read = try #require(reads.first)
        read()
        #expect(completions == 1)
        #expect(board.string(forType: .string) == "original")
        reads[1]()
        #expect(board.string(forType: .string) == "retry")
        clock.runAll()
        #expect(board.string(forType: .string) == "original")
    }

    @Test func backgroundSnapshotReturnsToMainBeforePostingAndRestoring() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] },
            readClipboard: { work in DispatchQueue.global().async { work() } }, schedule: { delay, action in
            if delay < 1 { DispatchQueue.main.async(execute: action) }
            return ScheduledOperation(cancellation: {})
        }, postPaste: { #expect(Thread.isMainThread); return true })
        let result: String? = await withCheckedContinuation { continuation in
            writer.paste("phrase", validate: { #expect(Thread.isMainThread); $0(nil) }, canSubmit: { true }) {
                #expect(Thread.isMainThread)
                continuation.resume(returning: $0)
            }
        }
        #expect(result == nil)
        #expect(board.string(forType: .string) == "original")
    }

    @Test func productionHelperRoundTripsMultipleClipboardFormats() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let binaryType = NSPasteboard.PasteboardType("example.helper-test")
        board.setString("original", forType: .string)
        board.setData(Data([0, 1, 255]), forType: binaryType)
        let executable = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/VoiceInputBuddy")
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        let writer = CommonPhraseClipboardPaste(board: board, modifierFlags: { [] }, snapshotExecutableURL: executable,
            schedule: { delay, action in
                if delay < 1 { DispatchQueue.main.async { action() } }
                return ScheduledOperation(cancellation: {})
            }, postPaste: { board.string(forType: .string) == "phrase" })
        let result: String? = await withCheckedContinuation { continuation in
            writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) {
                continuation.resume(returning: $0)
            }
        }
        #expect(result == nil)
        #expect(board.string(forType: .string) == "original")
        #expect(board.data(forType: binaryType) == Data([0, 1, 255]))
    }

    @Test func browserAndTerminalRoutesPreferNativePaste() {
        for terminal in ["com.apple.Terminal", "com.googlecode.iterm2", "org.alacritty", "com.mitchellh.ghostty"] {
            #expect(CommonPhraseInserter.prefersPaste(bundleIdentifier: terminal, electron: false, webContent: false))
        }
        #expect(CommonPhraseInserter.prefersPaste(bundleIdentifier: "com.google.Chrome", electron: false, webContent: false))
        #expect(CommonPhraseInserter.prefersPaste(bundleIdentifier: "com.apple.Safari", electron: false, webContent: false))
        #expect(CommonPhraseInserter.prefersPaste(bundleIdentifier: "example.editor", electron: true, webContent: false))
        #expect(CommonPhraseInserter.prefersPaste(bundleIdentifier: "example.browser", electron: false, webContent: true))
        #expect(!CommonPhraseInserter.prefersPaste(bundleIdentifier: "example.native", electron: false, webContent: false))
    }
}

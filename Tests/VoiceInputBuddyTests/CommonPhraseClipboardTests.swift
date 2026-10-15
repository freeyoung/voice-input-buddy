import AppKit
import Testing
@testable import VoiceInputBuddy

@Suite("Common phrase clipboard fallback")
@MainActor
struct CommonPhraseClipboardTests {
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
        let writer = CommonPhraseClipboardPaste(board: board, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: {
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
        let writer = CommonPhraseClipboardPaste(board: board, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: { true })
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
        let writer = CommonPhraseClipboardPaste(board: board, readClipboard: { $0() }, postPaste: {
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
        let writer = CommonPhraseClipboardPaste(board: board, readClipboard: { $0() }, postPaste: {
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
        var writer: CommonPhraseClipboardPaste? = .init(board: board, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: { submitted })
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
        let writer = CommonPhraseClipboardPaste(board: board, readClipboard: { $0() }, schedule: clock.voiceSchedule, postPaste: { posts += 1; return true })
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
        let writer = CommonPhraseClipboardPaste(board: board, readClipboard: { $0() }, postPaste: {
            Issue.record("Must not paste without a complete snapshot"); return true
        })
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) { #expect($0 == "clipboard_write_failed") }
        #expect(board.changeCount == count)
        #expect(board.data(forType: type) == original)
    }

    @Test func aDelayedSnapshotCannotReplaceClipboardAfterTheDeadline() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let clock = ControlledTestScheduler()
        var reads: [() -> Void] = []
        var completions = 0
        let writer = CommonPhraseClipboardPaste(board: board, readClipboard: { reads.append($0) },
            schedule: clock.voiceSchedule, postPaste: { Issue.record("Late snapshot must not paste"); return true })
        writer.paste("phrase", validate: { $0(nil) }, canSubmit: { true }) {
            #expect($0 == "clipboard_write_failed"); completions += 1
        }
        #expect(board.string(forType: .string) == "original")
        clock.runAll()
        #expect(completions == 1)
        writer.paste("retry", validate: { $0(nil) }, canSubmit: { true }) { #expect($0 == "clipboard_write_failed") }
        #expect(reads.count == 1)
        let read = try #require(reads.first)
        read()
        #expect(completions == 1)
        #expect(board.string(forType: .string) == "original")
    }

    @Test func backgroundSnapshotReturnsToMainBeforePostingAndRestoring() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        let writer = CommonPhraseClipboardPaste(board: board, schedule: { delay, action in
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

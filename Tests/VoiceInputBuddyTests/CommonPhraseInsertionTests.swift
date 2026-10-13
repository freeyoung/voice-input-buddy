import AppKit
import Testing
@testable import VoiceInputBuddy

@Suite("Common phrase clipboard transactions")
@MainActor
struct CommonPhraseInsertionTests {
    /// Uses a private named pasteboard. The user's general clipboard is never read or written.
    private func run(_ body: (NSPasteboard) throws -> Void) rethrows {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original", forType: .string)
        try body(board)
    }

    @Test func successfulPasteRestoresEveryOriginalClipboardFormat() {
        run { board in
            let custom = NSPasteboard.PasteboardType("test.buddy.binary")
            let bytes = Data([0, 1, 255])
            board.setData(bytes, forType: custom)
            var scheduled: [() -> Void] = []
            var results: [String] = []
            let inserter = CommonPhraseInserter(pasteboard: board, validateTarget: { _ in nil },
                postPaste: { #expect(board.string(forType: .string) == "phrase"); return true },
                schedule: { scheduled.append($0) }, logger: { _ in })
            inserter.insert("phrase", into: 100) { results.append($0) }
            #expect(results.isEmpty)
            #expect(scheduled.count == 1)
            scheduled.removeFirst()()
            #expect(results == ["common_phrases.paste_submitted"])
            #expect(board.string(forType: .string) == "original")
            #expect(board.data(forType: custom) == bytes)
        }
    }

    @Test func userCopyDuringPasteIsPreservedInsteadOfRestored() {
        run { board in
            var scheduled: [() -> Void] = []
            var results: [String] = []
            let inserter = CommonPhraseInserter(pasteboard: board, validateTarget: { _ in nil },
                postPaste: { true }, schedule: { scheduled.append($0) }, logger: { _ in })
            inserter.insert("phrase", into: 100) { results.append($0) }
            board.clearContents()
            board.setString("user copied later", forType: .string)
            scheduled.removeFirst()()
            #expect(board.string(forType: .string) == "user copied later")
            #expect(results == ["common_phrases.paste_submitted"])
        }
    }

    @Test func invalidTargetDoesNotTouchClipboardOrSendKeys() {
        run { board in
            let originalChange = board.changeCount
            var posts = 0
            var result: String?
            let inserter = CommonPhraseInserter(pasteboard: board, validateTarget: { _ in "input_unavailable" },
                postPaste: { posts += 1; return true }, schedule: { _ in Issue.record("No restoration needed") }, logger: { _ in })
            inserter.insert("phrase", into: 100) { result = $0 }
            #expect(posts == 0)
            #expect(board.changeCount == originalChange)
            #expect(result == "common_phrases.error.input_unavailable")
        }
    }

    @Test func targetChangeAfterClipboardWriteCancelsPasteAndRestoresClipboard() {
        run { board in
            var checks = 0
            var posts = 0
            var scheduled: [() -> Void] = []
            var result: String?
            let inserter = CommonPhraseInserter(pasteboard: board, validateTarget: { _ in
                checks += 1
                return checks == 1 ? nil : "target_changed"
            }, postPaste: { posts += 1; return true }, schedule: { scheduled.append($0) }, logger: { _ in })
            inserter.insert("phrase", into: 100) { result = $0 }
            #expect(posts == 0)
            scheduled.removeFirst()()
            #expect(board.string(forType: .string) == "original")
            #expect(result == "common_phrases.error.target_changed")
        }
    }

    @Test func failedKeySubmissionRestoresClipboardAndReportsFailure() {
        run { board in
            var scheduled: [() -> Void] = []
            var result: String?
            let inserter = CommonPhraseInserter(pasteboard: board, validateTarget: { _ in nil },
                postPaste: { false }, schedule: { scheduled.append($0) }, logger: { _ in })
            inserter.insert("phrase", into: 100) { result = $0 }
            scheduled.removeFirst()()
            #expect(board.string(forType: .string) == "original")
            #expect(result == "common_phrases.error.paste_failed")
        }
    }

    @Test func cancellationDropsQueuedPasteButFinishesActiveRestoration() {
        run { board in
            var scheduled: [() -> Void] = []
            var posts = 0
            var results: [String: String] = [:]
            let inserter = CommonPhraseInserter(pasteboard: board, validateTarget: { _ in nil },
                postPaste: { posts += 1; return true }, schedule: { scheduled.append($0) }, logger: { _ in })
            inserter.insert("first", into: 100) { results["first"] = $0 }
            inserter.insert("second", into: 100) { results["second"] = $0 }
            inserter.cancelPending()
            #expect(results["second"] == "common_phrases.error.cancelled")
            #expect(results["first"] == nil)
            scheduled.removeFirst()()
            #expect(results["first"] == "common_phrases.paste_submitted")
            #expect(posts == 1)
            #expect(board.string(forType: .string) == "original")
            #expect(scheduled.isEmpty)
        }
    }

    @Test func consecutivePastesUseSeparateSnapshotsAndCompleteInOrder() {
        run { board in
            var scheduled: [() -> Void] = []
            var submitted: [String] = []
            var completed: [String] = []
            let inserter = CommonPhraseInserter(pasteboard: board, validateTarget: { _ in nil },
                postPaste: { submitted.append(board.string(forType: .string) ?? ""); return true },
                schedule: { scheduled.append($0) }, logger: { _ in })
            inserter.insert("first", into: 100) { _ in completed.append("first") }
            inserter.insert("second", into: 100) { _ in completed.append("second") }
            #expect(submitted == ["first"])
            scheduled.removeFirst()()
            #expect(completed == ["first"])
            #expect(submitted == ["first", "second"])
            scheduled.removeFirst()()
            #expect(completed == ["first", "second"])
            #expect(board.string(forType: .string) == "original")
        }
    }
}

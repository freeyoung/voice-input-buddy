import AppKit
import Testing
@testable import VoiceInputBuddy

@Suite("Common phrase accessible insertion")
@MainActor
struct CommonPhraseInsertionTests {
    @Test func successfulInsertionNeverTouchesClipboard() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original secret", forType: .string)
        let change = board.changeCount
        var calls: [(String, pid_t)] = []
        var reply: ((String?) -> Void)?
        var result: String?
        let inserter = CommonPhraseInserter(write: { text, pid, completion in
            calls.append((text, pid)); reply = completion
        }, logger: { _ in })
        inserter.insert("phrase", into: 100) { result = $0 }
        #expect(calls.count == 1)
        #expect(calls[0].0 == "phrase")
        #expect(calls[0].1 == 100)
        #expect(result == nil)
        reply?(nil)
        #expect(result == "common_phrases.inserted")
        #expect(board.changeCount == change)
        #expect(board.string(forType: .string) == "original secret")
    }

    @Test func unavailableTargetReportsFailureWithoutSendingPaste() {
        var result: String?
        let inserter = CommonPhraseInserter(write: { _, _, completion in
            completion("input_unavailable")
        }, logger: { _ in })
        inserter.insert("phrase", into: 100) { result = $0 }
        #expect(result == "common_phrases.error.input_unavailable")
    }

    @Test func cancellationDropsQueuedRequestsAndLetsActiveInsertionFinish() {
        var replies: [(String?) -> Void] = []
        var texts: [String] = []
        var results: [String: String] = [:]
        let inserter = CommonPhraseInserter(write: { text, _, completion in
            texts.append(text); replies.append(completion)
        }, logger: { _ in })
        inserter.insert("first", into: 100) { results["first"] = $0 }
        inserter.insert("second", into: 100) { results["second"] = $0 }
        inserter.cancelPending()
        #expect(results["second"] == "common_phrases.error.cancelled")
        #expect(texts == ["first"])
        replies[0](nil)
        #expect(results["first"] == "common_phrases.inserted")
    }

    @Test func consecutiveInsertionsCompleteInOrder() {
        var replies: [(String?) -> Void] = []
        var texts: [String] = []
        var results: [String] = []
        let inserter = CommonPhraseInserter(write: { text, _, completion in
            texts.append(text); replies.append(completion)
        }, logger: { _ in })
        inserter.insert("first", into: 100) { results.append($0) }
        inserter.insert("second", into: 100) { results.append($0) }
        #expect(texts == ["first"])
        replies[0](nil)
        #expect(texts == ["first", "second"])
        replies[1]("target_changed")
        #expect(results == ["common_phrases.inserted", "common_phrases.error.target_changed"])
    }

    @Test func secureFieldMetadataBlocksInsertionButOrdinaryFieldsRemainAvailable() {
        func permits(subrole: String = "", enabled: Bool = true, protected: Bool = false,
                     identifier: String = "") -> Bool {
            CommonPhraseInserter.permitsInsertion(role: kAXTextFieldRole, subrole: subrole,
                enabled: enabled, protectedContent: protected, identifier: identifier)
        }
        #expect(permits())
        #expect(!permits(subrole: kAXSecureTextFieldSubrole))
        #expect(!permits(protected: true))
        #expect(!permits(enabled: false))
        #expect(!permits(identifier: "api_key"))
        for semanticText in ["密码", "输入口令", "信用卡号码", "Credit Card", "Passcode", "API Key"] {
            #expect(!permits(identifier: semanticText))
        }
        #expect(!CommonPhraseInserter.permitsInsertion(role: kAXTextFieldRole, subrole: "",
            enabled: true, protectedContent: false, identifier: "Composer", secureInputEnabled: true))
    }
}

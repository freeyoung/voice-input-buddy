import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Common phrase storage transactions")
@MainActor
struct CommonPhraseStorageTests {
    private func phrase(_ id: String, text: String = "测试") -> CommonPhrase {
        CommonPhrase(id: id, chineseText: text, chineseLabel: "标签", englishText: "Test", englishLabel: "Label")
    }
    private var bundled: CommonPhraseArchive {
        CommonPhraseArchive(entries: [phrase("builtin-one"), phrase("builtin-two", text: "第二项")],
            bindings: ["ok": "builtin-one", "left": "builtin-one", "up": "builtin-two"])
    }
    private func run(_ body: (CommonPhraseStore, UserDefaults, Data) throws -> Void) throws {
        let name = "phrase-unit-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let data = try JSONEncoder().encode(bundled)
        let store = CommonPhraseStore(defaults: defaults, builtInData: data)
        #expect(store.isAvailable)
        try body(store, defaults, data)
    }

    @Test func editingBundledPhraseCreatesUserCopyAndRetargetsEveryBinding() throws {
        try run { store, defaults, data in
            let id = try store.save(phrase("builtin-one", text: "已修改"), replacing: "builtin-one")
            #expect(id.hasPrefix("user-"))
            #expect(store.phrase(for: .ok)?.id == id)
            #expect(store.phrase(for: .left)?.id == id)
            let reopened = CommonPhraseStore(defaults: defaults, builtInData: data)
            #expect(reopened.phrase(for: .ok)?.chineseText == "已修改")
            #expect(reopened.phrase(for: .left)?.id == id)
            #expect(reopened.archive.entries.allSatisfy { $0.id != "builtin-one" })
        }
    }

    @Test func createAssignReorderDeleteRoundTripsWithoutDanglingBindings() throws {
        try run { store, defaults, data in
            let id = try store.save(phrase("user-new"), replacing: nil)
            try store.assign(.right, to: id)
            try store.assign(.down, to: id)
            try store.move(id, by: -1)
            let reopened = CommonPhraseStore(defaults: defaults, builtInData: data)
            #expect(reopened.archive.entries.map(\.id) == ["builtin-one", id, "builtin-two"])
            #expect(reopened.phrase(for: .right)?.id == id)
            try reopened.delete(id)
            let final = CommonPhraseStore(defaults: defaults, builtInData: data)
            #expect(final.phrase(for: .right) == nil)
            #expect(final.phrase(for: .down) == nil)
            #expect(final.phrase(for: .ok)?.id == "builtin-one")
        }
    }

    @Test func invalidEditsNeverReplacePersistedArchive() throws {
        try run { store, defaults, data in
            try store.assign(.right, to: "builtin-two")
            let original = store.archive
            var invalid = phrase("user-invalid")
            invalid.chineseText = "  "
            #expect(throws: CommonPhraseStore.StoreError.self) { try store.save(invalid, replacing: nil) }
            #expect(throws: CommonPhraseStore.StoreError.self) { try store.assign(.power, to: "builtin-one") }
            #expect(throws: CommonPhraseStore.StoreError.self) { try store.assign(.ok, to: "missing") }
            #expect(throws: CommonPhraseStore.StoreError.self) { try store.save(phrase("builtin-one"), replacing: nil) }
            #expect(store.archive == original)
            #expect(CommonPhraseStore(defaults: defaults, builtInData: data).archive == original)
        }
    }

    @Test func invalidImportsAreAtomicAndValidImportPreservesEditedBundledContent() throws {
        try run { store, defaults, data in
            let original = store.archive
            var invalid = bundled
            invalid.bindings["ok"] = "missing"
            #expect(throws: CommonPhraseStore.StoreError.self) { try store.importData(JSONEncoder().encode(invalid)) }
            invalid = bundled
            invalid.entries.append(invalid.entries[0])
            #expect(throws: CommonPhraseStore.StoreError.self) { try store.importData(JSONEncoder().encode(invalid)) }
            #expect(store.archive == original)
            var edited = bundled
            edited.entries[0].chineseText = "外部编辑"
            try store.importData(JSONEncoder().encode(edited))
            let id = try #require(store.phrase(for: .ok)?.id)
            #expect(id.hasPrefix("user-"))
            #expect(store.phrase(for: .left)?.id == id)
            #expect(CommonPhraseStore(defaults: defaults, builtInData: data).phrase(for: .ok)?.chineseText == "外部编辑")
        }
    }

    @Test func deletingBundledPhraseStaysDeletedOnReload() throws {
        try run { store, defaults, data in
            try store.delete("builtin-one")
            let reopened = CommonPhraseStore(defaults: defaults, builtInData: data)
            #expect(reopened.archive.entries.map(\.id) == ["builtin-two"])
            #expect(reopened.phrase(for: .ok) == nil)
            #expect(reopened.phrase(for: .left) == nil)
        }
    }

    @Test func corruptedSavedArchiveCanRecoverThroughValidatedImport() throws {
        try run { _, defaults, data in
            defaults.set(Data("invalid-json".utf8), forKey: "commonPhrases.archive.v1")
            let broken = CommonPhraseStore(defaults: defaults, builtInData: data)
            #expect(!broken.isAvailable && broken.loadFailed)
            try broken.importData(data)
            #expect(broken.isAvailable && !broken.loadFailed)
            #expect(CommonPhraseStore(defaults: defaults, builtInData: data).phrase(for: .ok)?.id == "builtin-one")
        }
    }

    @Test func entryLimitRejectsAnAdditionalPhraseWithoutLosingExistingEntries() throws {
        try run { store, _, _ in
            let full = CommonPhraseArchive(entries: (0..<500).map { phrase("user-\($0)") }, bindings: [:])
            try store.importData(JSONEncoder().encode(full))
            let original = store.archive
            #expect(throws: CommonPhraseStore.StoreError.self) { try store.save(phrase("user-extra"), replacing: nil) }
            #expect(store.archive == original)
        }
    }
}

@Suite("Common phrase input ownership")
struct CommonPhraseOwnershipTests {
    @Test func foreignRemoteCannotChooseOrReleaseOwnersPhrase() {
        var routing = CommonPhraseRouting()
        routing.open(source: "first")
        #expect(routing.handle(.up, phase: .press, source: "second") == .unhandled)
        #expect(routing.owner == "first")
        #expect(routing.handle(.up, phase: .press, source: "first") == .insert(.up))
        #expect(routing.handle(.up, phase: .press, source: "first") == .consumed)
        routing.close()
        #expect(routing.handle(.up, phase: .release, source: "second") == .unhandled)
        #expect(routing.handle(.up, phase: .release, source: "first") == .consumed)
        #expect(routing.handle(.up, phase: .release, source: "first") == .unhandled)
    }
    @Test func reopeningDoesNotLeakHeldReleaseFromPreviousOwner() {
        var routing = CommonPhraseRouting()
        routing.open(source: "first")
        #expect(routing.handle(.back, phase: .press, source: "first") == .close)
        routing.open(source: "second")
        routing.reset(source: "unrelated")
        #expect(routing.claims(.back, source: "first"))
        #expect(routing.handle(.back, phase: .release, source: "first") == .consumed)
        #expect(routing.owner == "second")
        #expect(routing.handle(.ok, phase: .press, source: "second") == .insert(.ok))
        routing.reset(source: "second")
        #expect(!routing.claims(.ok, source: "second"))
    }
    @Test(arguments: [RemoteButton.power, .tv, .volumeUp])
    func unrelatedButtonsDoNotClosePanel(button: RemoteButton) {
        var routing = CommonPhraseRouting()
        routing.open(source: "first")
        #expect(routing.handle(button, phase: .press, source: "first") == .unhandled)
        #expect(routing.owner == "first")
    }
}

import Foundation
import Testing
@testable import SkinnyDip

/// Saved undo history is tagged with the Editor Backend that wrote it; the
/// other backend restores the text only (ADR-0010).
struct ScratchHistoryBackendTests {
    private let text = "hello"
    private let history = #"{"doc":"hello","done":[],"undone":[]}"#

    @Test func codeMirrorHistoryImportsUnderCodeMirror() {
        let restored = ScratchHistory.restorable(
            forText: text, storedHistoryJSON: history, storedBackend: "codeMirror", current: .codeMirror
        )
        #expect(restored == history)
    }

    @Test func codeMirrorHistoryIsDroppedUnderNative() {
        let restored = ScratchHistory.restorable(
            forText: text, storedHistoryJSON: history, storedBackend: "codeMirror", current: .native
        )
        #expect(restored == nil)
    }

    @Test func untaggedLegacyHistoryCountsAsCodeMirror() {
        #expect(ScratchHistory.restorable(
            forText: text, storedHistoryJSON: history, storedBackend: nil, current: .codeMirror
        ) == history)
        #expect(ScratchHistory.restorable(
            forText: text, storedHistoryJSON: history, storedBackend: nil, current: .native
        ) == nil)
    }

    @Test func historyIsTaggedWithTheBackendThatWroteIt() {
        #expect(ScratchHistory.tag(for: history, backend: .codeMirror) == "codeMirror")
        #expect(ScratchHistory.tag(for: nil, backend: .codeMirror) == nil)
    }
}

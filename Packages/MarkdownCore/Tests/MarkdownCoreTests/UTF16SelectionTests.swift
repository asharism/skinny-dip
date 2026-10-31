import Testing
import MarkdownCore

/// CodeMirror reports selection as UTF-16 code-unit offsets, same as JavaScript strings.
struct UTF16SelectionTests {
    @Test func asciiRange() {
        let text = "hello"
        let range = UTF16Selection.range(in: text, from: 1, to: 4)
        #expect(range.map { String(text[$0]) } == "ell")
    }

    @Test func emojiUsesTwoUTF16CodeUnits() {
        let text = "a🎉b"
        #expect(text.utf16.count == 4)
        let range = UTF16Selection.range(in: text, from: 1, to: 3)
        #expect(range.map { String(text[$0]) } == "🎉")
    }

    @Test func emptyRangeAtCursor() {
        let text = "abc"
        let range = UTF16Selection.range(in: text, from: 2, to: 2)
        #expect(range?.isEmpty == true)
    }

    @Test func outOfBoundsReturnsNil() {
        #expect(UTF16Selection.range(in: "hi", from: 0, to: 99) == nil)
        #expect(UTF16Selection.range(in: "hi", from: -1, to: 1) == nil)
        #expect(UTF16Selection.range(in: "hi", from: 2, to: 1) == nil)
    }

    @Test func fullDocumentRange() {
        let text = "line\n"
        let range = UTF16Selection.range(in: text, from: 0, to: text.utf16.count)
        #expect(range.map { String(text[$0]) } == text)
    }
}

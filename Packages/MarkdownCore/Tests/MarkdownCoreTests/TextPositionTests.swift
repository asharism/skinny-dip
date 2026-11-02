import Testing
@testable import MarkdownCore

struct TextPositionTests {
    @Test func startOfText() {
        let position = TextPosition.lineColumn(in: "Hello", utf16Offset: 0)
        #expect(position.line == 1)
        #expect(position.column == 1)
    }

    @Test func afterNewline() {
        let position = TextPosition.lineColumn(in: "a\nb", utf16Offset: 2)
        #expect(position.line == 2)
        #expect(position.column == 1)
    }

    @Test func emojiColumnCountsCharacters() {
        let position = TextPosition.lineColumn(in: "a👍b", utf16Offset: 3)
        #expect(position.line == 1)
        #expect(position.column == 3)
    }

    @Test func pastTheEndIsClamped() {
        let position = TextPosition.lineColumn(in: "hi", utf16Offset: 99)
        #expect(position.line == 1)
        #expect(position.column == 3)
    }
}

import Testing
import MarkdownCore

/// The native editor's line-number gutter (#76) and scroll sync count logical
/// lines in UTF-16 offsets, the units `NSTextView` uses.
struct LineNumberingTests {
    @Test func emptyDocumentHasOneLine() {
        let lines = LineNumbering("")
        #expect(lines.count == 1)
        #expect(lines.starts == [0])
        #expect(lines.line(atUTF16: 0) == 1)
    }

    @Test func trailingNewlineAddsEmptyNumberedLine() {
        let lines = LineNumbering("one\ntwo\n")
        #expect(lines.count == 3)
        #expect(lines.starts == [0, 4, 8])
        #expect(lines.line(atUTF16: 8) == 3)
    }

    @Test func crlfCountsAsOneBreak() {
        let lines = LineNumbering("a\r\nb\rc\nd")
        #expect(lines.count == 4)
        #expect(lines.starts == [0, 3, 5, 7])
        // Between the \r and the \n is still the first line.
        #expect(lines.line(atUTF16: 2) == 1)
    }

    @Test func lineForOffsetAtLineStartAndEnd() {
        let lines = LineNumbering("abc\ndef\nghi")
        #expect(lines.line(atUTF16: 0) == 1)
        #expect(lines.line(atUTF16: 3) == 1)
        #expect(lines.line(atUTF16: 4) == 2)
        #expect(lines.line(atUTF16: 7) == 2)
        #expect(lines.line(atUTF16: 8) == 3)
        #expect(lines.line(atUTF16: 11) == 3)
        // Out of range clamps to the first and last line.
        #expect(lines.line(atUTF16: -5) == 1)
        #expect(lines.line(atUTF16: 99) == 3)
        #expect(lines.start(ofLine: 2) == 4)
        #expect(lines.start(ofLine: 0) == 0)
        #expect(lines.start(ofLine: 99) == 8)
    }

    @Test func emojiAndCJKUseUTF16Offsets() {
        // 👋🏽 is four UTF-16 units, 日本 two.
        let lines = LineNumbering("👋🏽\n日本\nx")
        #expect(lines.starts == [0, 5, 8])
        #expect(lines.line(atUTF16: 4) == 1)
        #expect(lines.line(atUTF16: 6) == 2)
        #expect(lines.line(atUTF16: 8) == 3)
    }

    @Test func digitsHaveATwoDigitMinimum() {
        #expect(LineNumbering.digits(forLineCount: 1) == 2)
        #expect(LineNumbering.digits(forLineCount: 99) == 2)
        #expect(LineNumbering.digits(forLineCount: 100) == 3)
        #expect(LineNumbering.digits(forLineCount: 1000) == 4)
    }
}

import MarkdownCore
import Testing

/// Line commands (#92): ⌥↑/⌥↓ move, ⇧⌥↑/⇧⌥↓ duplicate, ⌘⇧K delete, ⌘L select.
/// They act on the logical lines the selection touches (`lineRanges(touching:)`).
struct LineCommandTests {
    let up: (EditorState) -> TextEdit? = { MarkdownEditing.moveLines($0, up: true) }
    let down: (EditorState) -> TextEdit? = { MarkdownEditing.moveLines($0, up: false) }
    let duplicateUp: (EditorState) -> TextEdit? = { MarkdownEditing.duplicateLines($0, up: true) }
    let duplicateDown: (EditorState) -> TextEdit? = { MarkdownEditing.duplicateLines($0, up: false) }
    let delete = MarkdownEditing.deleteLines
    let select = MarkdownEditing.selectLine

    // MARK: Move

    @Test func moveUp() {
        expectEdit(up, from: "a\nb|\nc", to: "b|\na\nc")
        expectEdit(up, from: "a\nb\nc|", to: "a\nc|\nb")
        expectEdit(up, from: "a|\nb\nc", to: nil)
        expectEdit(up, from: "a\n«b\nc»\nd", to: "«b\nc»\na\nd")
    }

    @Test func moveDown() {
        expectEdit(down, from: "a|\nb\nc", to: "b\na|\nc")
        expectEdit(down, from: "a\nb|\nc", to: "a\nc\nb|")
        expectEdit(down, from: "a\nb\nc|", to: nil)
        expectEdit(down, from: "a\n«b\nc»\nd", to: "a\nd\n«b\nc»")
    }

    /// A selection ending at column 0 doesn't touch that line.
    @Test func moveSelectionEndingAtColumnZero() {
        expectEdit(up, from: "a\n«b\n»c", to: "«b\n»a\nc")
        expectEdit(down, from: "«a\n»b\nc", to: "b\n«a\n»c")
    }

    /// The last line has no terminator: no gluing, no new trailing break.
    @Test func moveKeepsFinalNewlineState() {
        expectEdit(up, from: "a\nb|", to: "b|\na")
        expectEdit(down, from: "a|\nb", to: "b\na|")
        expectEdit(up, from: "a\nb|\n", to: "b|\na\n")
        expectEdit(down, from: "a|\nb\n", to: "b\na|\n")
        // The empty "line" after a final newline isn't a line: nothing to move.
        expectEdit(down, from: "a\nb|\n", to: nil)
        expectEdit(up, from: "a\nb\n|", to: nil)
    }

    @Test func moveCRLF() {
        expectEdit(up, from: "a\r\nb|\r\nc", to: "b|\r\na\r\nc")
        expectEdit(down, from: "a\r\nb|", to: nil)
        expectEdit(down, from: "a|\r\nb", to: "b\r\na|")
    }

    @Test func moveEmoji() {
        expectEdit(up, from: "👋🏽\nb👋🏽|", to: "b👋🏽|\n👋🏽")
        expectEdit(down, from: "👋🏽|x\nb", to: "b\n👋🏽|x")
    }

    // MARK: Duplicate

    @Test func duplicateDownEndsOnTheCopy() {
        expectEdit(duplicateDown, from: "a|\nb", to: "a\na|\nb")
        expectEdit(duplicateDown, from: "a\nb|\nc", to: "a\nb\nb|\nc")
        expectEdit(duplicateDown, from: "a\nb|", to: "a\nb\nb|")
        expectEdit(duplicateDown, from: "«a\nb»\nc", to: "a\nb\n«a\nb»\nc")
        expectEdit(duplicateDown, from: "«a\n»b", to: "a\n«a\n»b")
    }

    @Test func duplicateUpStaysOnTheOriginal() {
        expectEdit(duplicateUp, from: "a|\nb", to: "a|\na\nb")
        expectEdit(duplicateUp, from: "a\nb|", to: "a\nb|\nb")
        expectEdit(duplicateUp, from: "«a\nb»\nc", to: "«a\nb»\na\nb\nc")
    }

    @Test func duplicateCRLFAndEmoji() {
        expectEdit(duplicateDown, from: "a\r\nb👋🏽|", to: "a\r\nb👋🏽\r\nb👋🏽|")
        expectEdit(duplicateDown, from: "👋🏽|\r\nb", to: "👋🏽\r\n👋🏽|\r\nb")
    }

    // MARK: Delete

    @Test func deleteLandsOnTheNextLineAtTheSameColumn() {
        expectEdit(delete, from: "ab|c\nxyz", to: "xy|z")
        expectEdit(delete, from: "a\nbc|\nx", to: "a\nx|")
        expectEdit(delete, from: "«a\nb»\nc", to: "|c")
        expectEdit(delete, from: "«a\n»b", to: "|b")
    }

    @Test func deleteLastLineLandsOnThePreviousLine() {
        expectEdit(delete, from: "abc\nx|y", to: "a|bc")
        expectEdit(delete, from: "a\nxyz|", to: "a|")
        expectEdit(delete, from: "only|", to: "|")
        expectEdit(delete, from: "a\nb|\n", to: "a\n|")
        expectEdit(delete, from: "a\n|", to: nil)
        expectEdit(delete, from: "|", to: nil)
    }

    @Test func deleteCRLFAndEmoji() {
        expectEdit(delete, from: "a|b\r\nc", to: "c|")
        expectEdit(delete, from: "a\r\nb|", to: "a|")
        // Same column clamps to a whole character, never inside an emoji.
        expectEdit(delete, from: "abc|\n👋🏽", to: "|👋🏽")
        expectEdit(delete, from: "abcd|\n👋🏽z", to: "👋🏽|z")
    }

    // MARK: Select

    @Test func selectLineThenExtend() {
        expectEdit(select, from: "a|b\nc\nd", to: "«ab\n»c\nd")
        expectEdit(select, from: "«ab\n»c\nd", to: "«ab\nc\n»d")
        expectEdit(select, from: "«ab\nc\n»d", to: "«ab\nc\nd»")
        expectEdit(select, from: "«ab\nc\nd»", to: nil)
        expectEdit(select, from: "a\nb|", to: "a\n«b»")
        expectEdit(select, from: "a«b\nc»d\ne", to: "«ab\ncd\n»e")
    }

    @Test func selectLineCRLFAndEmoji() {
        expectEdit(select, from: "a|\r\nb", to: "«a\r\n»b")
        expectEdit(select, from: "👋🏽|\nb", to: "«👋🏽\n»b")
    }

    @Test func selectLineIsSelectionOnly() throws {
        let edit = try #require(MarkdownEditing.selectLine(EditFixture.state("a|\nb")))
        #expect(edit.isSelectionOnly)
    }
}

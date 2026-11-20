import MarkdownCore
import Testing

/// Smart ⌘← (#95): the start of the line's content first, then column 0.
struct SmartLineStartTests {
    /// Moves the caret in `fixture` (caret notation, `|`) and renders where it lands.
    private func smart(_ fixture: String) -> String {
        let state = EditFixture.state(fixture)
        let target = MarkdownEditing.smartLineStart(caret: state.selection.lowerBound, in: state.text)
        return EditFixture.render(EditorState(text: state.text, caret: target))
    }

    @Test(arguments: [
        // The issue's examples.
        ("  - [ ] ta|sk", "  - [ ] |task"),
        ("  - [ ] |task", "|  - [ ] task"),
        ("> > quo|te", "> > |quote"),
        ("plain te|xt", "|plain text"),
        ("|plain text", "|plain text"),
        // Ordered items, tab indents, plain indents.
        ("10. x|", "10. |x"),
        ("10. |x", "|10. x"),
        ("\t- it|em", "\t- |item"),
        ("    indented|", "    |indented"),
        ("    |indented", "|    indented"),
        // Inside the prefix: forward to the content, as VS Code's Home does.
        ("  -| [ ] task", "  - [ ] |task"),
        // An empty item: the caret is already at its content start.
        ("- |", "|- "),
        ("> |", "|> "),
        // Emoji before the caret: UTF-16 offsets.
        ("- 👋🏽 he|llo", "- |👋🏽 hello"),
        ("👋🏽 a|b", "|👋🏽 ab"),
        // Only the caret's own line.
        ("one\n- tw|o\nthree", "one\n- |two\nthree"),
        ("one\n- |two\nthree", "one\n|- two\nthree"),
        // `\r\n` documents.
        ("a\r\n- b|c\r\nd", "a\r\n- |bc\r\nd"),
        ("a\r\n- |bc\r\nd", "a\r\n|- bc\r\nd"),
        ("a\r\nb|", "a\r\n|b"),
        // An empty line and an empty document.
        ("a\n|\nb", "a\n|\nb"),
        ("|", "|"),
    ])
    func movesToContentThenColumnZero(from: String, to: String) {
        #expect(smart(from) == to)
    }

    @Test func pressingTwiceTogglesBetweenContentAndColumnZero() {
        let text = "- [ ] some task"
        let first = MarkdownEditing.smartLineStart(caret: text.utf16.count, in: text)
        #expect(first == 6)
        let second = MarkdownEditing.smartLineStart(caret: first, in: text)
        #expect(second == 0)
        #expect(MarkdownEditing.smartLineStart(caret: second, in: text) == 6)
    }
}

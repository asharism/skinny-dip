import MarkdownCore
import Testing

/// Tab / ⇧Tab and ⌘] / ⌘[ (#91): indent and outdent with spaces, never a tab
/// character. `indent` is Tab, `indentLines` is ⌘], `outdent` is both ⇧Tab and ⌘[.
struct IndentTests {
    let indent = MarkdownEditing.indent
    let indentLines = MarkdownEditing.indentLines
    let outdent = MarkdownEditing.outdent

    // MARK: Issue examples

    @Test func issueExamples() {
        expectEdit(indent, from: "- a\n- b|", to: "- a\n  - b|")
        expectEdit(indent, from: "1. a\n2. b|", to: "1. a\n   2. b|")
        expectEdit(outdent, from: "  - b|", to: "- b|")
        expectEdit(indent, from: "|x", to: "    |x")
        expectEdit(indent, from: "ab|c", to: "ab  |c")
    }

    // MARK: List items

    @Test func listItemIndentUsesThePreviousSiblingsContentOffset() {
        expectEdit(indent, from: "10. a\n11. b|", to: "10. a\n    11. b|")
        expectEdit(indent, from: "- a\n- |", to: "- a\n  - |")
        // The caret anywhere on the item indents the whole item.
        expectEdit(indent, from: "- a\n- b|c", to: "- a\n  - b|c")
        expectEdit(indent, from: "- a\n|- b", to: "- a\n  |- b")
        // Deeper items in between are skipped; the sibling at the same indent wins.
        expectEdit(indent, from: "1. a\n   - x\n2. b|", to: "1. a\n   - x\n   2. b|")
        // Nested sibling.
        expectEdit(indent, from: "- a\n  - b\n  - c|", to: "- a\n  - b\n    - c|")
    }

    @Test func listItemWithNoPreviousSiblingUsesItsOwnMarker() {
        expectEdit(indent, from: "- a|", to: "  - a|")
        expectEdit(indent, from: "12. a|", to: "    12. a|")
        // The parent isn't a sibling.
        expectEdit(indent, from: "1. a\n   - b|", to: "1. a\n     - b|")
    }

    @Test func mixedBulletAndOrderedSiblings() {
        expectEdit(indent, from: "- a\n1. b|", to: "- a\n  1. b|")
        expectEdit(indent, from: "1. a\n- b|", to: "1. a\n   - b|")
    }

    @Test func listItemOutdentMovesToTheParentsIndent() {
        expectEdit(outdent, from: "- a\n  - b\n    - c|", to: "- a\n  - b\n  - c|")
        expectEdit(outdent, from: "1. a\n   - b|", to: "1. a\n- b|")
        expectEdit(outdent, from: "     - b|", to: "- b|")
        expectEdit(outdent, from: "- a\n  |- b", to: "- a\n|- b")
    }

    @Test func listItemInsideFencedCodeIsCode() {
        expectEdit(indent, from: "```\n- a\n- b|\n```", to: "```\n- a\n- b |\n```")
        expectEdit(indent, from: "```\n|x\n```", to: "```\n    |x\n```")
    }

    // MARK: Other lines

    @Test func caretInsertsSpacesToTheNextTabStop() {
        expectEdit(indent, from: "abcd|", to: "abcd    |")
        expectEdit(indent, from: "abc|", to: "abc |")
        expectEdit(indent, from: "|", to: "    |")
        expectEdit(indent, from: "a\n\n|", to: "a\n\n    |")
    }

    @Test func selectionWithinOneLineIndentsTheLine() {
        expectEdit(indent, from: "a«bc»d", to: "    a«bc»d")
        expectEdit(indent, from: "«abc»", to: "«    abc»")
        expectEdit(indent, from: "- a\n- «b»", to: "- a\n  - «b»")
    }

    @Test func outdentRemovesUpToFourSpaces() {
        expectEdit(outdent, from: "      x|", to: "  x|")
        expectEdit(outdent, from: "  x|", to: "x|")
        expectEdit(outdent, from: "  |  x", to: "|x")
        expectEdit(outdent, from: "    «ab»", to: "«ab»")
    }

    @Test func outdentRemovesOneLeadingTab() {
        expectEdit(outdent, from: "\t\tx|", to: "\tx|")
        expectEdit(outdent, from: "\tx|", to: "x|")
        expectEdit(outdent, from: "\t- b|", to: "- b|")
    }

    @Test func outdentWithNoIndentDeclines() {
        expectEdit(outdent, from: "x|", to: nil)
        expectEdit(outdent, from: "- b|", to: nil)
        expectEdit(outdent, from: "|", to: nil)
        expectEdit(outdent, from: "«a\nb»", to: nil)
    }

    // MARK: Multi-line selections

    @Test func multiLineSelectionIndentsEveryLineAndSkipsBlankOnes() {
        expectEdit(indent, from: "a«b\n\nc»d", to: "«    ab\n\n    cd»")
        expectEdit(indentLines, from: "a«b\n\nc»d", to: "«    ab\n\n    cd»")
        expectEdit(outdent, from: "    a«b\n\n    c»d", to: "«ab\n\ncd»")
    }

    @Test func multiLineSelectionOfListItems() {
        expectEdit(indent, from: "«- a\n- b»", to: "«  - a\n  - b»")
        expectEdit(outdent, from: "- a\n  «- b\n  - c»", to: "- a\n«- b\n- c»")
        expectEdit(indent, from: "«- a\nplain»", to: "«  - a\n    plain»")
    }

    @Test func selectionEndingAtColumnZeroDoesNotTouchThatLine() {
        expectEdit(indent, from: "«a\nb\n»c", to: "«    a\n    b\n»c")
        expectEdit(outdent, from: "«  a\n  b\n»  c", to: "«a\nb\n»  c")
        // One whole line, terminator included: the line stays selected.
        expectEdit(indent, from: "«a\n»b", to: "«    a\n»b")
    }

    @Test func multiLineOfOnlyBlankLinesChangesNothingButIsHandled() {
        let state = EditFixture.state("«\n\n»x")
        let edit = indent(state)
        #expect(edit?.isSelectionOnly == true)
        #expect(edit?.selection == state.selection)
    }

    // MARK: ⌘] always indents the line

    @Test func indentLinesIndentsTheLineEvenWithACaret() {
        expectEdit(indentLines, from: "ab|c", to: "    ab|c")
        expectEdit(indentLines, from: "|x", to: "    |x")
        expectEdit(indentLines, from: "- a\n- b|", to: "- a\n  - b|")
        expectEdit(indentLines, from: "|", to: nil)
    }

    // MARK: UTF-16

    @Test func emojiInTheLine() {
        // 👋🏽 is one character (column) but four UTF-16 units.
        expectEdit(indent, from: "👋🏽|x", to: "👋🏽   |x")
        expectEdit(indent, from: "- 👋🏽\n- b👋🏽|", to: "- 👋🏽\n  - b👋🏽|")
        expectEdit(outdent, from: "    👋🏽|", to: "👋🏽|")
        expectEdit(indent, from: "«👋🏽\n👋🏽»", to: "«    👋🏽\n    👋🏽»")
    }

    @Test func crlfDocuments() {
        expectEdit(indent, from: "- a\r\n- b|", to: "- a\r\n  - b|")
        expectEdit(outdent, from: "- a\r\n  - b|\r\nc", to: "- a\r\n- b|\r\nc")
        expectEdit(indent, from: "«a\r\n\r\nb»", to: "«    a\r\n\r\n    b»")
        expectEdit(indent, from: "x\r\nab|", to: "x\r\nab  |")
    }

    @Test func neverInsertsATabCharacter() {
        for fixture in ["|", "a|", "- a\n- b|", "«a\nb»", "\t|x", "```\n|\n```"] {
            let state = EditFixture.state(fixture)
            for command in [indent, indentLines] {
                guard let edit = command(state) else { continue }
                #expect(!edit.replacement.contains("\t"), "from \(fixture.debugDescription)")
            }
        }
    }
}

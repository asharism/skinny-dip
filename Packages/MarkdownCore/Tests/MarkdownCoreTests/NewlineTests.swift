import MarkdownCore
import Testing

/// Enter continues the list or blockquote the caret is in (#90).
struct NewlineTests {
    let newline = MarkdownEditing.newline

    @Test func continuesBullets() {
        expectEdit(newline, from: "- a|", to: "- a\n- |")
        expectEdit(newline, from: "* a|", to: "* a\n* |")
        expectEdit(newline, from: "+ a|", to: "+ a\n+ |")
        expectEdit(newline, from: "  - a|", to: "  - a\n  - |")
        expectEdit(newline, from: "\t- a|", to: "\t- a\n\t- |")
    }

    @Test func continuesOrderedItemsWithTheNextNumberOnly() {
        expectEdit(newline, from: "1. a|", to: "1. a\n2. |")
        expectEdit(newline, from: "9) a|", to: "9) a\n10) |")
        // Don't renumber the items below (ADR-0012).
        expectEdit(newline, from: "1. a|\n2. b", to: "1. a\n2. |\n2. b")
    }

    @Test func newTaskItemsAreUnchecked() {
        expectEdit(newline, from: "- [ ] a|", to: "- [ ] a\n- [ ] |")
        expectEdit(newline, from: "- [x] a|", to: "- [x] a\n- [ ] |")
        expectEdit(newline, from: "1. [X] a|", to: "1. [X] a\n2. [ ] |")
    }

    @Test func continuesBlockquotes() {
        expectEdit(newline, from: "> a|", to: "> a\n> |")
        expectEdit(newline, from: "> - a|", to: "> - a\n> - |")
        expectEdit(newline, from: "> > a|", to: "> > a\n> > |")
    }

    @Test func splitsAnItem() {
        expectEdit(newline, from: "- a|b", to: "- a\n- |b")
        expectEdit(newline, from: "- |a", to: "- \n- |a")
    }

    @Test func emptyItemEndsTheList() {
        expectEdit(newline, from: "- |", to: "|")
        expectEdit(newline, from: "  - |", to: "|")
        expectEdit(newline, from: "- [ ] |", to: "|")
        expectEdit(newline, from: "1. |", to: "|")
        expectEdit(newline, from: "> |", to: "|")
        expectEdit(newline, from: ">|", to: "|")
        expectEdit(newline, from: "> - |", to: "|")
        expectEdit(newline, from: "- a\n- |\nnext", to: "- a\n|\nnext")
    }

    @Test func indentedPlainLineKeepsItsIndent() {
        expectEdit(newline, from: "   plain|", to: "   plain\n   |")
        expectEdit(newline, from: "\tplain|", to: "\tplain\n\t|")
    }

    @Test func declines() {
        expectEdit(newline, from: "plain|", to: nil)
        expectEdit(newline, from: "|", to: nil)
        expectEdit(newline, from: "# Heading|", to: nil)
        // Caret before the content start: an ordinary newline.
        expectEdit(newline, from: "|- a", to: nil)
        expectEdit(newline, from: "-| a", to: nil)
        expectEdit(newline, from: " | - a", to: nil)
        // A whitespace-only line: nothing to continue.
        expectEdit(newline, from: "   |", to: nil)
        // A thematic break isn't a list item.
        expectEdit(newline, from: "- - -|", to: nil)
        expectEdit(newline, from: "* * *|", to: nil)
    }

    @Test func declinesInsideFencedCode() {
        expectEdit(newline, from: "```\n- a|\n```", to: nil)
        expectEdit(newline, from: "~~~\n  indented|", to: nil)
        expectEdit(newline, from: "```\ncode\n```\n- a|", to: "```\ncode\n```\n- a\n- |")
    }

    @Test func singleLineSelectionIsReplacedFirst() {
        expectEdit(newline, from: "- a«bc»", to: "- a\n- |")
        expectEdit(newline, from: "- a«b»c", to: "- a\n- |c")
        expectEdit(newline, from: "- «abc»", to: "|")
        expectEdit(newline, from: "«- »a", to: nil)
        expectEdit(newline, from: "plain «text»", to: nil)
    }

    @Test func multiLineSelectionDeclines() {
        expectEdit(newline, from: "- «a\n- b»", to: nil)
        expectEdit(newline, from: "- a«\n»- b", to: nil)
    }

    @Test func emojiInTheItem() {
        expectEdit(newline, from: "- 👋🏽|", to: "- 👋🏽\n- |")
        expectEdit(newline, from: "- 👋🏽|b", to: "- 👋🏽\n- |b")
        expectEdit(newline, from: "👋🏽\n> a|", to: "👋🏽\n> a\n> |")
    }

    @Test func usesTheLinesOwnLineEnding() {
        expectEdit(newline, from: "- a|\r\n- b", to: "- a\r\n- |\r\n- b")
        // The last line has no terminator: use the line above's.
        expectEdit(newline, from: "x\r\n- a|", to: "x\r\n- a\r\n- |")
        expectEdit(newline, from: "- a\r\n- |", to: "- a\r\n|")
    }
}

import MarkdownCore
import Testing

/// The Editing Command model (ADR-0012): states, edits and the line helpers
/// every command builds on. All offsets are UTF-16, as `NSTextView` reports them.
struct EditingModelTests {
    // MARK: EditFixture

    @Test func fixtureRoundTrips() {
        let caret = EditFixture.state("- a|")
        #expect(caret == EditorState(text: "- a", selection: 3..<3))
        #expect(EditFixture.render(caret) == "- a|")

        let selection = EditFixture.state("a«👋🏽»b")
        #expect(selection == EditorState(text: "a👋🏽b", selection: 1..<5))
        #expect(EditFixture.render(selection) == "a«👋🏽»b")
    }

    // MARK: TextEdit

    @Test func appliedReplacesUTF16RangeAroundEmoji() {
        let state = EditFixture.state("a👋🏽|b")
        let edit = TextEdit(range: 1..<5, replacement: "🎉", selection: 3..<3)
        let result = edit.applied(to: state)
        #expect(result.text == "a🎉b")
        #expect(EditFixture.render(result) == "a🎉|b")
    }

    @Test func appliedKeepsCRLFIntact() {
        let state = EditFixture.state("- a|\r\n- b")
        let edit = TextEdit(range: 3..<3, replacement: "\r\n- ", selection: 7..<7)
        #expect(EditFixture.render(edit.applied(to: state)) == "- a\r\n- |\r\n- b")
    }

    @Test func expectEditReadsAsOneLine() {
        let upper: (EditorState) -> TextEdit? = { state in
            state.selection.isEmpty ? nil : TextEdit(range: state.selection, replacement: "X", selection: state.selection.lowerBound + 1 ..< state.selection.lowerBound + 1)
        }
        expectEdit(upper, from: "a«b»c", to: "aX|c")
        expectEdit(upper, from: "a|bc", to: nil)
    }

    @Test func selectionOnlyEdit() {
        let state = EditFixture.state("a|bc")
        let edit = TextEdit.select(1..<3)
        #expect(edit.isSelectionOnly)
        #expect(EditFixture.render(edit.applied(to: state)) == "a«bc»")
        #expect(!TextEdit(range: 0..<1, replacement: "", selection: 0..<0).isSelectionOnly)
    }

    // MARK: lineRange(containing:in:)

    @Test func lineRangeFirstMiddleLast() {
        let text = "one\ntwo\r\nthree"
        #expect(MarkdownEditing.lineRange(containing: 0, in: text) == LineRange(content: 0..<3, terminator: .lf))
        #expect(MarkdownEditing.lineRange(containing: 3, in: text) == LineRange(content: 0..<3, terminator: .lf))
        #expect(MarkdownEditing.lineRange(containing: 4, in: text) == LineRange(content: 4..<7, terminator: .crlf))
        #expect(MarkdownEditing.lineRange(containing: 7, in: text) == LineRange(content: 4..<7, terminator: .crlf))
        #expect(MarkdownEditing.lineRange(containing: 9, in: text) == LineRange(content: 9..<14, terminator: .none))
        #expect(MarkdownEditing.lineRange(containing: 14, in: text) == LineRange(content: 9..<14, terminator: .none))
        #expect(MarkdownEditing.lineRange(containing: 4, in: text).full == 4..<9)
        #expect(MarkdownEditing.lineRange(containing: 4, in: text).text(in: text) == "two")
    }

    @Test func lineRangeEmptyLinesAndDocument() {
        #expect(MarkdownEditing.lineRange(containing: 0, in: "") == LineRange(content: 0..<0, terminator: .none))
        // A trailing break leaves an empty last line.
        #expect(MarkdownEditing.lineRange(containing: 2, in: "a\n") == LineRange(content: 2..<2, terminator: .none))
        #expect(MarkdownEditing.lineRange(containing: 2, in: "a\n\nb") == LineRange(content: 2..<2, terminator: .lf))
        #expect(MarkdownEditing.lineRange(containing: 1, in: "a\rb") == LineRange(content: 0..<1, terminator: .cr))
    }

    @Test func lineRangeWithEmoji() {
        let text = "👋🏽 hi\nnext"
        #expect(MarkdownEditing.lineRange(containing: 2, in: text) == LineRange(content: 0..<7, terminator: .lf))
        #expect(MarkdownEditing.lineRange(containing: 8, in: text) == LineRange(content: 8..<12, terminator: .none))
    }

    @Test func lineEndingFollowsTheLine() {
        #expect(MarkdownEditing.lineEnding(near: 0, in: "a\r\nb") == "\r\n")
        // The last line has no terminator: borrow the line above's, else `\n`.
        #expect(MarkdownEditing.lineEnding(near: 4, in: "a\r\nb") == "\r\n")
        #expect(MarkdownEditing.lineEnding(near: 1, in: "a") == "\n")
    }

    // MARK: lineRanges(touching:in:)

    @Test func lineRangesTouchingSelection() {
        let text = "one\ntwo\nthree"
        #expect(MarkdownEditing.lineRanges(touching: 1..<1, in: text).map(\.content) == [0..<3])
        #expect(MarkdownEditing.lineRanges(touching: 1..<5, in: text).map(\.content) == [0..<3, 4..<7])
        #expect(MarkdownEditing.lineRanges(touching: 0..<13, in: text).map(\.content) == [0..<3, 4..<7, 8..<13])
    }

    @Test func selectionEndingAtColumnZeroDoesNotTouchThatLine() {
        let text = "one\ntwo\nthree"
        #expect(MarkdownEditing.lineRanges(touching: 0..<4, in: text).map(\.content) == [0..<3])
        #expect(MarkdownEditing.lineRanges(touching: 1..<8, in: text).map(\.content) == [0..<3, 4..<7])
        // An empty selection at column 0 is on that line.
        #expect(MarkdownEditing.lineRanges(touching: 4..<4, in: text).map(\.content) == [4..<7])
        let crlf = "a\r\nb\r\nc"
        #expect(MarkdownEditing.lineRanges(touching: 0..<3, in: crlf).map(\.content) == [0..<1])
    }

    // MARK: linePrefix(_:)

    struct PrefixCase: CustomTestStringConvertible, Sendable {
        let line: String
        let expected: LinePrefix
        var testDescription: String { line.debugDescription }
    }

    static let prefixCases: [PrefixCase] = [
        PrefixCase(line: "- a", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), contentStart: 2)),
        PrefixCase(line: "  * a", expected: LinePrefix(indent: 2, indentLength: 2, quoteEnd: 2, list: ListMarker(kind: .bullet("*"), range: 2..<3), contentStart: 4)),
        PrefixCase(line: "+ a", expected: LinePrefix(list: ListMarker(kind: .bullet("+"), range: 0..<1), contentStart: 2)),
        PrefixCase(line: "1. a", expected: LinePrefix(list: ListMarker(kind: .ordered(number: 1, delimiter: "."), range: 0..<2), contentStart: 3)),
        PrefixCase(line: "10) a", expected: LinePrefix(list: ListMarker(kind: .ordered(number: 10, delimiter: ")"), range: 0..<3), contentStart: 4)),
        PrefixCase(line: "- [ ] a", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), task: TaskBox(isChecked: false, range: 2..<5), contentStart: 6)),
        PrefixCase(line: "- [x] a", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), task: TaskBox(isChecked: true, range: 2..<5), contentStart: 6)),
        PrefixCase(line: "- [X] a", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), task: TaskBox(isChecked: true, range: 2..<5), contentStart: 6)),
        PrefixCase(line: "- [ ]", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), contentStart: 2)),
        PrefixCase(line: "- [ ]a", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), contentStart: 2)),
        PrefixCase(line: "> a", expected: LinePrefix(quoteDepth: 1, quoteEnd: 2, contentStart: 2)),
        PrefixCase(line: ">a", expected: LinePrefix(quoteDepth: 1, quoteEnd: 1, contentStart: 1)),
        PrefixCase(line: "> ", expected: LinePrefix(quoteDepth: 1, quoteEnd: 2, contentStart: 2)),
        PrefixCase(line: "> > - a", expected: LinePrefix(quoteDepth: 2, quoteEnd: 4, list: ListMarker(kind: .bullet("-"), range: 4..<5), contentStart: 6)),
        PrefixCase(line: "\t- a", expected: LinePrefix(indent: 4, indentLength: 1, quoteEnd: 1, list: ListMarker(kind: .bullet("-"), range: 1..<2), contentStart: 3)),
        PrefixCase(line: "-a", expected: LinePrefix()),
        PrefixCase(line: "- ", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), contentStart: 2)),
        PrefixCase(line: "-", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), contentStart: 1)),
        PrefixCase(line: "#tag", expected: LinePrefix()),
        PrefixCase(line: "**bold**", expected: LinePrefix()),
        PrefixCase(line: "1.5 apples", expected: LinePrefix()),
        PrefixCase(line: "   plain", expected: LinePrefix(indent: 3, indentLength: 3, quoteEnd: 3, contentStart: 3)),
        PrefixCase(line: "", expected: LinePrefix()),
        PrefixCase(line: "- 👋🏽", expected: LinePrefix(list: ListMarker(kind: .bullet("-"), range: 0..<1), contentStart: 2)),
    ]

    @Test(arguments: prefixCases)
    func linePrefix(_ c: PrefixCase) {
        #expect(MarkdownEditing.linePrefix(Substring(c.line)) == c.expected)
    }

    @Test func linePrefixOffsetsAreRelativeToTheSubstring() {
        let text = "intro\n  - [ ] task"
        let line = MarkdownEditing.lineRange(containing: 8, in: text).text(in: text)
        let prefix = MarkdownEditing.linePrefix(line)
        #expect(prefix.contentStart == 8)
        #expect(prefix.list?.kind == .bullet("-"))
        #expect(prefix.task?.isChecked == false)
    }

    @Test func listMarkerConveniences() {
        let ordered = ListMarker(kind: .ordered(number: 9, delimiter: ")"), range: 0..<2)
        #expect(ordered.isOrdered)
        #expect(ordered.number == 9)
        #expect(ordered.delimiter == ")")
        let bullet = ListMarker(kind: .bullet("*"), range: 0..<1)
        #expect(!bullet.isOrdered)
        #expect(bullet.number == nil)
        #expect(bullet.delimiter == "*")
    }

    // MARK: isInsideFencedCode(line:in:)

    @Test func insideBacktickFence() {
        let text = "a\n```swift\n- code\n```\n- b"
        #expect(!MarkdownEditing.isInsideFencedCode(line: 0, in: text))   // a
        #expect(!MarkdownEditing.isInsideFencedCode(line: 2, in: text))   // the opening fence
        #expect(MarkdownEditing.isInsideFencedCode(line: 11, in: text))   // - code
        #expect(MarkdownEditing.isInsideFencedCode(line: 18, in: text))   // the closing fence
        #expect(!MarkdownEditing.isInsideFencedCode(line: 22, in: text))  // - b
    }

    @Test func insideTildeFence() {
        let text = "~~~\n- code\n```\n- still code\n~~~\n- out"
        #expect(MarkdownEditing.isInsideFencedCode(line: 4, in: text))
        // A ``` line doesn't close a ~~~ fence.
        #expect(MarkdownEditing.isInsideFencedCode(line: 15, in: text))
        #expect(!MarkdownEditing.isInsideFencedCode(line: 33, in: text))
    }

    @Test func unclosedFenceRunsToTheEnd() {
        let text = "x\n````\n- a\n```\n- b"
        // A shorter fence doesn't close a longer one.
        #expect(MarkdownEditing.isInsideFencedCode(line: 7, in: text))
        #expect(MarkdownEditing.isInsideFencedCode(line: 15, in: text))
    }

    @Test func fenceWithCRLFAndInlineBackticks() {
        let text = "```\r\ncode\r\n```\r\nafter ``` x"
        #expect(MarkdownEditing.isInsideFencedCode(line: 5, in: text))
        #expect(!MarkdownEditing.isInsideFencedCode(line: 16, in: text))
        #expect(!MarkdownEditing.isInsideFencedCode(line: 0, in: "``x``\ny"))
        #expect(!MarkdownEditing.isInsideFencedCode(line: 6, in: "``x``\ny"))
    }
}

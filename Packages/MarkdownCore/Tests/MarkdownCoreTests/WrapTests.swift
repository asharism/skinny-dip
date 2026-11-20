import MarkdownCore
import Testing

/// Typing a pair character over a selection wraps it (#93). The selection
/// stays on the inner text, so a second `*` makes it bold.
struct WrapTests {
    private func wrap(_ character: Character) -> (EditorState) -> TextEdit? {
        { MarkdownEditing.wrap($0, with: character) }
    }

    @Test func eachPairWraps() {
        expectEdit(wrap("*"), from: "a «word» b", to: "a *«word»* b")
        expectEdit(wrap("_"), from: "a «word» b", to: "a _«word»_ b")
        expectEdit(wrap("`"), from: "a «word» b", to: "a `«word»` b")
        expectEdit(wrap("~"), from: "a «word» b", to: "a ~«word»~ b")
        expectEdit(wrap("["), from: "a «word» b", to: "a [«word»] b")
        expectEdit(wrap("("), from: "a «word» b", to: "a («word») b")
        expectEdit(wrap("\""), from: "a «word» b", to: "a \"«word»\" b")
    }

    @Test func otherCharactersReplaceAsUsual() {
        expectEdit(wrap("'"), from: "a «word» b", to: nil)
        expectEdit(wrap("<"), from: "a «word» b", to: nil)
        expectEdit(wrap("x"), from: "a «word» b", to: nil)
        expectEdit(wrap("]"), from: "a «word» b", to: nil)
    }

    @Test func starTwiceMakesBold() throws {
        let state = EditFixture.state("a «word» b")
        let once = try #require(MarkdownEditing.wrap(state, with: "*")).applied(to: state)
        let twice = try #require(MarkdownEditing.wrap(once, with: "*")).applied(to: once)
        #expect(EditFixture.render(twice) == "a **«word»** b")
    }

    @Test func needsANonEmptySelection() {
        expectEdit(wrap("*"), from: "a |word", to: nil)
    }

    @Test func multiLineSelectionReplacesAsUsual() {
        expectEdit(wrap("*"), from: "«one\ntwo»", to: nil)
        expectEdit(wrap("*"), from: "«one\r\ntwo»", to: nil)
        expectEdit(wrap("*"), from: "«one\n»two", to: nil)
    }

    @Test func emojiInsideTheSelection() {
        expectEdit(wrap("*"), from: "hi «👋🏽 there»!", to: "hi *«👋🏽 there»*!")
        expectEdit(wrap("`"), from: "«👋🏽»", to: "`«👋🏽»`")
    }

    @Test func crlfLineWraps() {
        expectEdit(wrap("*"), from: "one\r\n«two»\r\nthree", to: "one\r\n*«two»*\r\nthree")
    }

    @Test func editIsMinimal() throws {
        let edit = try #require(MarkdownEditing.wrap(EditFixture.state("a «word» b"), with: "*"))
        #expect(edit.range == 2..<6)
        #expect(edit.replacement == "*word*")
    }
}

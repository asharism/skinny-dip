import MarkdownCore
import Testing

/// ⌘B and ⌘I (#93): toggle `**` and `*` around the selection or the word
/// under the caret. Bold is `**` and italic `*`, as Paste as Markdown writes.
///
/// The rule: count the `*` run touching each side of the inner text, inside
/// or just outside the selection. The shorter run is the emphasis level:
/// 1 italic, 2 bold, 3 both. Bold is on at 2 or more, italic at an odd count.
/// A toggle removes or adds its marker right next to the inner text.
struct EmphasisToggleTests {
    private let bold: (EditorState) -> TextEdit? = { MarkdownEditing.toggleEmphasis($0, marker: "**") }
    private let italic: (EditorState) -> TextEdit? = { MarkdownEditing.toggleEmphasis($0, marker: "*") }

    @Test func wrapsTheSelection() {
        expectEdit(bold, from: "a «word» b", to: "a **«word»** b")
        expectEdit(italic, from: "a «word» b", to: "a *«word»* b")
        expectEdit(bold, from: "«two words»", to: "**«two words»**")
    }

    @Test func unwrapsMarkersJustOutsideTheSelection() {
        expectEdit(bold, from: "a **«word»** b", to: "a «word» b")
        expectEdit(italic, from: "a *«word»* b", to: "a «word» b")
    }

    @Test func unwrapsMarkersJustInsideTheSelection() {
        expectEdit(bold, from: "a «**word**» b", to: "a «word» b")
        expectEdit(italic, from: "a «*word*» b", to: "a «word» b")
    }

    @Test func boldTwiceRestoresThePlainWord() throws {
        let state = EditFixture.state("a «word» b")
        let once = try #require(bold(state)).applied(to: state)
        let twice = try #require(bold(once)).applied(to: once)
        #expect(EditFixture.render(twice) == "a «word» b")
    }

    @Test func wrapsTheWordUnderTheCaret() {
        expectEdit(bold, from: "a wo|rd b", to: "a **wo|rd** b")
        expectEdit(italic, from: "a wo|rd b", to: "a *wo|rd* b")
        expectEdit(bold, from: "a |word b", to: "a **|word** b")
        expectEdit(bold, from: "a word| b", to: "a **word|** b")
    }

    @Test func unwrapsTheWordUnderTheCaret() {
        expectEdit(bold, from: "a **wo|rd** b", to: "a wo|rd b")
        expectEdit(italic, from: "a *wo|rd* b", to: "a wo|rd b")
    }

    @Test func emptySpotInsertsAPairWithTheCaretInside() {
        expectEdit(bold, from: "|", to: "**|**")
        expectEdit(italic, from: "|", to: "*|*")
        expectEdit(bold, from: "a | b", to: "a **|** b")
        expectEdit(bold, from: "one\n|\ntwo", to: "one\n**|**\ntwo")
    }

    @Test func emptyPairTogglesBackOff() {
        expectEdit(bold, from: "**|**", to: "|")
        expectEdit(italic, from: "*|*", to: "|")
    }

    /// The bold markers are not italic markers: ⌘I inside bold adds a third star.
    @Test func italicInsideBoldAddsAThirdStar() {
        expectEdit(italic, from: "**«bold»**", to: "***«bold»***")
        expectEdit(italic, from: "«**bold**»", to: "***«bold»***")
        expectEdit(italic, from: "**bo|ld**", to: "***bo|ld***")
    }

    @Test func boldInsideItalicAddsTwoStars() {
        expectEdit(bold, from: "*«it»*", to: "***«it»***")
    }

    @Test func togglesOnBoldItalic() {
        expectEdit(bold, from: "«***x***»", to: "*«x»*")
        expectEdit(bold, from: "***«x»***", to: "*«x»*")
        expectEdit(italic, from: "***«x»***", to: "**«x»**")
        expectEdit(bold, from: "***x|***", to: "*x|*")
    }

    @Test func starsInsideTheTextAreNotMarkers() {
        expectEdit(bold, from: "«*a* b»", to: "**«*a* b»**")
        expectEdit(bold, from: "«a*b»", to: "**«a*b»**")
    }

    @Test func emojiAndCRLF() {
        expectEdit(bold, from: "hi «👋🏽»\r\nnext", to: "hi **«👋🏽»**\r\nnext")
        expectEdit(bold, from: "«👋🏽 hi»", to: "**«👋🏽 hi»**")
        expectEdit(bold, from: "👋🏽 caf|é", to: "👋🏽 **caf|é**")
    }

    @Test func multiLineSelectionDeclines() {
        expectEdit(bold, from: "«one\ntwo»", to: nil)
    }

    @Test func editsAreMinimal() throws {
        let wrap = try #require(bold(EditFixture.state("a «word» b")))
        #expect(wrap.range == 2..<6)
        let unwrap = try #require(bold(EditFixture.state("a **«word»** b")))
        #expect(unwrap.range == 2..<10)
        #expect(unwrap.replacement == "word")
    }
}

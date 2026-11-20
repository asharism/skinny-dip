import Foundation
import MarkdownCore
import Testing

/// Caret notation for Editing Command tests (ADR-0012): `|` is the caret and
/// `«…»` a selection, so a case reads as one line:
///
///     expectEdit(MarkdownEditing.newline, from: "- a|", to: "- a\n- |")
///
/// The markers are never part of the text, so a fixture can't contain a literal
/// `|`, `«` or `»`; build that `EditorState` by hand.
enum EditFixture {
    /// `"- a|"` → text `"- a"`, caret at 3. `"«ab»c"` → selection 0..<2.
    /// Exactly one `|`, or one `«` followed by one `»`.
    static func state(_ fixture: String) -> EditorState {
        var text = ""
        var caret: Int?
        var start: Int?
        var end: Int?
        for character in fixture {
            switch character {
            case "|": caret = text.utf16.count
            case "«": start = text.utf16.count
            case "»": end = text.utf16.count
            default: text.append(character)
            }
        }
        if let start, let end, caret == nil, start <= end {
            return EditorState(text: text, selection: start..<end)
        }
        guard let caret, start == nil, end == nil else {
            preconditionFailure("EditFixture needs one `|` or one `«…»` pair: \(fixture.debugDescription)")
        }
        return EditorState(text: text, selection: caret..<caret)
    }

    /// The state back in caret notation: `|` for an empty selection, `«…»` otherwise.
    static func render(_ state: EditorState) -> String {
        let text = state.text as NSString
        let lower = text.substring(to: state.selection.lowerBound)
        let upper = text.substring(from: state.selection.upperBound)
        if state.selection.isEmpty { return lower + "|" + upper }
        let inner = text.substring(with: NSRange(location: state.selection.lowerBound, length: state.selection.count))
        return lower + "«" + inner + "»" + upper
    }
}

/// Runs `command` on `fixture` and renders the result, or `nil` when the command
/// declines ("not mine": the app falls through to AppKit).
func apply(_ command: (EditorState) -> TextEdit?, _ fixture: String) -> String? {
    let state = EditFixture.state(fixture)
    return command(state).map { EditFixture.render($0.applied(to: state)) }
}

/// One-line Editing Command case: `command` turns `from` into `to`. Pass
/// `to: nil` to require that the command declines.
func expectEdit(
    _ command: (EditorState) -> TextEdit?,
    from fixture: String,
    to expected: String?,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(apply(command, fixture) == expected, "from \(fixture.debugDescription)", sourceLocation: sourceLocation)
}

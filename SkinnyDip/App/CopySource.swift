import SwiftUI

/// What the copy commands need from the frontmost document: its Markdown Source
/// and the editor's selection in it. This is the seam between the editor and
/// the commands; whichever editor replaces the placeholder only has to publish one.
struct CopySource {
    var markdown: String
    /// `nil` or empty copies the whole document.
    var selection: Range<String.Index>?
}

/// Undo/redo menu state for the CodeMirror editor (Edit ▸ Undo/Redo).
struct EditorHistoryMenuState {
    var canUndo: Bool
    var canRedo: Bool
}

extension FocusedValues {
    @Entry var copySource: CopySource?
    @Entry var editorHistoryMenuState: EditorHistoryMenuState?
}

extension TextSelection {
    /// The single selected range in `text`, if it is one and still lies inside
    /// `text`. A multi-range selection copies the whole document rather than
    /// guessing how to join the pieces.
    func range(in text: String) -> Range<String.Index>? {
        guard case .selection(let range) = indices,
              range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex
        else { return nil }
        return range
    }
}

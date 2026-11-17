import SwiftUI

/// What the copy commands need from the frontmost document: its Markdown Source
/// and the editor's selection in it. This is the seam between the editor and
/// the commands; whichever editor replaces the placeholder only has to publish one.
struct CopySource {
    var markdown: String
    /// `nil` or empty: ⌘⇧C and ⌥⌘C copy the whole document, ⌘C copies nothing.
    var selection: Range<String.Index>?
    /// Which window should show the copy confirmation. Nil stays silent.
    var documentID: UUID?
}

/// Undo/redo menu state for the CodeMirror editor (Edit ▸ Undo/Redo).
struct EditorHistoryMenuState {
    var canUndo: Bool
    var canRedo: Bool
}

/// Cut/copy/paste availability for the Edit menu when a document is frontmost (ADR-0011).
struct EditorPasteboardMenuState {
    /// ⌘X: an editor selection, and the Preview doesn't have focus.
    var canCut: Bool
    /// ⌘C: a non-empty selection in whichever Card has focus.
    var canCopy: Bool
    /// ⌘⇧C and ⌥⌘C: a selection, or else a non-empty document to copy whole.
    var canCopyRichText: Bool
    var canPaste: Bool

    /// `previewSelection` is nil while the Preview doesn't have focus, otherwise
    /// whether the Preview has a non-empty selection.
    init(editorHasSelection: Bool, documentIsEmpty: Bool, previewSelection: Bool?, canPaste: Bool) {
        canCut = previewSelection == nil && editorHasSelection
        canCopy = previewSelection ?? editorHasSelection
        canCopyRichText = canCopy || !documentIsEmpty
        self.canPaste = canPaste
    }
}

extension FocusedValues {
    @Entry var copySource: CopySource?
    @Entry var editorHistoryMenuState: EditorHistoryMenuState?
    @Entry var editorPasteboardMenuState: EditorPasteboardMenuState?
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

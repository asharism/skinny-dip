import Foundation

/// CodeMirror undo depth. `editor.js` must contain this number.
public enum EditorHistory {
    /// Long enough that a drafting session can undo back to an empty document.
    public static let minimumDepth = 10_000
}

/// Undo step grouping for the CodeMirror history extension (milliseconds).
public enum EditorUndoGrouping {
    /// MarkEdit’s 300 ms default was too fine-grained ([MarkEdit #1582](https://github.com/MarkEdit-app/MarkEdit/issues/1582)).
    /// CodeMirror’s built-in 500 ms is still closer to per-word than TextEdit; 750 ms groups phrases without merging separate edits.
    public static let newGroupDelayMilliseconds = 750
}

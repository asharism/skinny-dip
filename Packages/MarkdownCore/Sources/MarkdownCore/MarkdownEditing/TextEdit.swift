import Foundation

/// What an Editing Command sees (ADR-0012): the Markdown Source and the one
/// selection, in UTF-16 offsets, the units `NSTextView` reports.
public struct EditorState: Equatable, Sendable {
    public var text: String
    /// UTF-16 offsets into `text`; empty for a caret.
    public var selection: Range<Int>

    public init(text: String, selection: Range<Int>) {
        self.text = text
        self.selection = selection
    }

    public init(text: String, caret: Int) {
        self.init(text: text, selection: caret..<caret)
    }
}

/// One Editing Command's change: replace `range` with `replacement`, then
/// select `selection`. The app applies it as one undo step. Keep `range` to
/// the span that changes, so spell-check marks and scroll position stay put.
public struct TextEdit: Equatable, Sendable {
    /// UTF-16 offsets in the old text.
    public var range: Range<Int>
    public var replacement: String
    /// UTF-16 offsets in the new text.
    public var selection: Range<Int>

    public init(range: Range<Int>, replacement: String, selection: Range<Int>) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// A pure selection change (⌘L): no text changes and the app adds no undo step.
    public static func select(_ selection: Range<Int>) -> TextEdit {
        TextEdit(range: selection.lowerBound..<selection.lowerBound, replacement: "", selection: selection)
    }

    /// True when the edit only moves the selection.
    public var isSelectionOnly: Bool { range.isEmpty && replacement.isEmpty }

    public func applied(to state: EditorState) -> EditorState {
        let text = (state.text as NSString).replacingCharacters(
            in: NSRange(location: range.lowerBound, length: range.count),
            with: replacement
        )
        return EditorState(text: text, selection: selection)
    }
}

/// Editing Commands (ADR-0012): pure `(EditorState) -> TextEdit?` functions,
/// where `nil` means "not mine" and the app falls through to AppKit. Each
/// feature extends this in its own file; the shared line helpers are in
/// `LineRanges.swift`, `LinePrefix.swift` and `FencedCode.swift`.
public enum MarkdownEditing {}

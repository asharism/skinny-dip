#if os(macOS)
import AppKit
import MarkdownCore

/// Enter continues the list or blockquote the caret is in (#90,
/// `MarkdownEditing.newline`). ⇧↩ also arrives as `insertNewline:`, so it's
/// told apart by the event's modifiers and stays a plain newline. ⌥↩ and ⌃↩
/// send other selectors and stay AppKit's.
extension NativeEditorTextView {
    override func insertNewline(_ sender: Any?) {
        if isShiftReturn || !perform(MarkdownEditing.newline) { super.insertNewline(sender) }
    }

    private var isShiftReturn: Bool {
        guard let event = NSApp.currentEvent, event.type == .keyDown else { return false }
        return event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
    }
}
#endif

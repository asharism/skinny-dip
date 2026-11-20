#if os(macOS)
import AppKit
import MarkdownCore

/// Line commands (#92): ⌥↑/⌥↓ move, ⇧⌥↑/⇧⌥↓ duplicate, ⌘⇧K delete, ⌘L select.
/// The Format menu's Lines items send these selectors; the focused editor also
/// claims the shortcuts in `performKeyEquivalent`, which AppKit asks before the
/// main menu and before the text view's own key bindings. They replace AppKit's
/// ⌥↑/⌥↓ (paragraph start or end) and ⇧⌥↑/⇧⌥↓ (extend to the paragraph) in
/// the Editor, as in VS Code and Sublime Text. ⌃A/⌃E and ⌘↑/⌘↓ stay AppKit's.
extension NativeEditorTextView {
    /// The shortcuts, matched on `charactersIgnoringModifiers` (lowercased) and
    /// the ⌘⌥⇧⌃ flags. `FormatCommands` shows the same keys; `MenuRoutingTests`
    /// checks the two agree.
    static let lineCommandShortcuts: [(key: String, modifiers: NSEvent.ModifierFlags, action: Selector)] = [
        (arrowUp, .option, #selector(moveLinesUp(_:))),
        (arrowDown, .option, #selector(moveLinesDown(_:))),
        (arrowUp, [.option, .shift], #selector(duplicateLinesUp(_:))),
        (arrowDown, [.option, .shift], #selector(duplicateLinesDown(_:))),
        ("k", [.command, .shift], #selector(deleteLines(_:))),
        ("l", .command, #selector(selectLine(_:))),
    ]

    private static let arrowUp = String(UnicodeScalar(NSUpArrowFunctionKey)!)
    private static let arrowDown = String(UnicodeScalar(NSDownArrowFunctionKey)!)

    static func lineCommand(for event: NSEvent) -> Selector? {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        return lineCommandShortcuts.first { $0.key == key && $0.modifiers == flags }?.action
    }

    /// Runs a line command's shortcut while this editor has focus. Unfocused
    /// (the Preview or a Settings field), it leaves the key to the menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, let action = Self.lineCommand(for: event) {
            _ = tryToPerform(action, with: self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc func moveLinesUp(_ sender: Any?) {
        perform { MarkdownEditing.moveLines($0, up: true) }
    }

    @objc func moveLinesDown(_ sender: Any?) {
        perform { MarkdownEditing.moveLines($0, up: false) }
    }

    @objc func duplicateLinesUp(_ sender: Any?) {
        perform { MarkdownEditing.duplicateLines($0, up: true) }
    }

    @objc func duplicateLinesDown(_ sender: Any?) {
        perform { MarkdownEditing.duplicateLines($0, up: false) }
    }

    @objc func deleteLines(_ sender: Any?) {
        perform(MarkdownEditing.deleteLines)
    }

    /// `NSResponder.selectLine(_:)` selects the wrapped row; ⌘L selects the
    /// logical line and extends. With several selections or marked text,
    /// AppKit's version runs; at the end of the document nothing happens.
    override func selectLine(_ sender: Any?) {
        if !perform(MarkdownEditing.selectLine), editorState == nil { super.selectLine(sender) }
    }
}
#endif

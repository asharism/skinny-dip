#if os(macOS)
import AppKit
import SwiftUI

/// The Format menu: Editing Commands with a menu item (ADR-0012). Each item
/// sends a selector down the responder chain, so it reaches the focused
/// `NativeEditorTextView` and does nothing with the Preview or a Settings field
/// focused. The Markdown rules live in `MarkdownCore/MarkdownEditing`; the text
/// view's action calls `perform(_:)`.
///
/// One section per feature, so parallel PRs each add lines only under their own
/// comment. Put a `Divider()` at the top of your section once a section above it
/// has items.
struct FormatCommands: Commands {
    var body: some Commands {
        CommandMenu(Self.menuTitle) {
            // Wrap: ⌘B ⌘I (#93)

            // Links: ⌘K (#94)

            // Indent: ⌘] ⌘[ (#91)

            // Lines: ⌥↑ ⌥↓ ⇧⌥↑ ⇧⌥↓ ⌘⇧K ⌘L (#92)
            Divider()
            Button("Move Line Up") { send(#selector(NativeEditorTextView.moveLinesUp(_:))) }
                .keyboardShortcut(.upArrow, modifiers: .option)
            Button("Move Line Down") { send(#selector(NativeEditorTextView.moveLinesDown(_:))) }
                .keyboardShortcut(.downArrow, modifiers: .option)
            Button("Duplicate Line Up") { send(#selector(NativeEditorTextView.duplicateLinesUp(_:))) }
                .keyboardShortcut(.upArrow, modifiers: [.option, .shift])
            Button("Duplicate Line Down") { send(#selector(NativeEditorTextView.duplicateLinesDown(_:))) }
                .keyboardShortcut(.downArrow, modifiers: [.option, .shift])
            Button("Delete Line") { send(#selector(NativeEditorTextView.deleteLines(_:))) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Select Line") { send(#selector(NSResponder.selectLine(_:))) }
                .keyboardShortcut("l")
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    static let menuTitle = "Format"

    /// SwiftUI shows a `CommandMenu` with no items as an empty dropdown, so the
    /// menu stays hidden until a section has an item. Once one does, this does
    /// nothing. Called at launch and whenever the app becomes active.
    @MainActor
    static func hideWhileEmpty() {
        guard let item = NSApp.mainMenu?.items.first(where: { $0.title == menuTitle }) else { return }
        let isEmpty = item.submenu?.items.isEmpty ?? true
        if item.isHidden != isEmpty { item.isHidden = isEmpty }
    }
}
#endif

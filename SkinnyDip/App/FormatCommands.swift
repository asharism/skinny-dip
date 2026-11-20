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
            Divider()
            Button("Indent") { send(#selector(NativeEditorTextView.skinnyDipIndent(_:))) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Outdent") { send(#selector(NativeEditorTextView.skinnyDipOutdent(_:))) }
                .keyboardShortcut("[", modifiers: .command)

            // Lines: ⌥↑ ⌥↓ ⇧⌥↑ ⇧⌥↓ ⌘⇧K ⌘L (#92)
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

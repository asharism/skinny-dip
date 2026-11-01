#if os(macOS)
import AppKit
import SwiftUI
import MarkdownCore

/// The Edit menu's pasteboard group, with Copy replaced by the three copy
/// commands. ⌘C is Copy as Rich Text because pasting into Outlook or Teams is
/// what the app is for; the plain system Copy would paste unformatted Markdown.
struct CopyCommands: Commands {
    @FocusedValue(\.copySource) private var source
    @FocusedValue(\.editorHistoryMenuState) private var historyMenuState
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { send(Self.undoSelector) }
                .keyboardShortcut("z")
                .disabled(!(historyMenuState?.canUndo ?? false))
            Button("Redo") { send(Self.redoSelector) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(historyMenuState?.canRedo ?? false))
        }

        // Replacing the group drops the system Cut, Paste and friends too, so they
        // come back here as first-responder actions, which every text view handles.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x")
            Button("Copy as Rich Text", action: copyAsRichText)
                .keyboardShortcut("c")
            Button("Copy as Markdown") {
                guard let source else { return }
                CopyWriter.writeMarkdown(markdown: source.markdown, selection: source.selection)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(source == nil)
            Button("Copy as HTML") {
                guard let source else { return }
                CopyWriter.writeHTML(markdown: source.markdown, selection: source.selection)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(source == nil)
            Button("Paste") { send(#selector(NSText.paste(_:))) }
                .keyboardShortcut("v")
            Button("Paste and Match Style") { send(#selector(NSTextView.pasteAsPlainText(_:))) }
                .keyboardShortcut("v", modifiers: [.command, .option, .shift])
            Button("Delete") { send(#selector(NSText.delete(_:))) }
            Button("Select All") { send(#selector(NSText.selectAll(_:))) }
                .keyboardShortcut("a")
        }
    }

    /// With no document in front (a Settings field, an open panel) ⌘C falls back
    /// to the system Copy, so copying still works everywhere.
    private func copyAsRichText() {
        guard let source else { return send(#selector(NSText.copy(_:))) }
        CopyWriter.writeRichText(markdown: source.markdown, selection: source.selection)
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    private static let undoSelector = Selector("skinyDipUndo:")
    private static let redoSelector = Selector("skinyDipRedo:")
}
#endif

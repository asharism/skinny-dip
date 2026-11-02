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
    @FocusedValue(\.editorPasteboardMenuState) private var pasteboardMenuState
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { send(Self.undoSelector) }
                .keyboardShortcut("z")
                .disabled(!(historyMenuState?.canUndo ?? false))
            Button("Redo") { send(Self.redoSelector) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!(historyMenuState?.canRedo ?? false))
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Preview") {
                NotificationCenter.default.post(name: .togglePreview, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        // Replacing the group drops the system Cut, Paste and friends too, so they
        // come back here as first-responder actions, which every text view handles.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x")
                .disabled(!(pasteboardMenuState?.canCut ?? true))
            Button("Copy as Rich Text", action: copyAsRichText)
                .keyboardShortcut("c")
                .disabled(!(pasteboardMenuState?.canCopy ?? true))
            Button("Copy as Markdown") {
                guard let source else { return }
                CopyWriter.writeMarkdown(markdown: source.markdown, selection: source.selection, documentID: source.documentID)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(source == nil)
            Button("Copy as HTML") {
                guard let source else { return }
                CopyWriter.writeHTML(markdown: source.markdown, selection: source.selection, documentID: source.documentID)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(source == nil)
            Button("Paste as Markdown", action: paste)
                .keyboardShortcut("v")
            Button("Paste and Match Style", action: pasteAsPlainText)
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
        CopyWriter.writeRichText(markdown: source.markdown, selection: source.selection, documentID: source.documentID)
    }

    private func paste() {
        if let editor = EditorWebView.pasteTarget() {
            editor.paste(nil)
        } else {
            send(#selector(NSText.paste(_:)))
        }
    }

    private func pasteAsPlainText() {
        if let editor = EditorWebView.pasteTarget() {
            editor.pasteAsPlainText(nil)
        } else {
            send(#selector(NSTextView.pasteAsPlainText(_:)))
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    static let undoSelector = #selector(EditorWebView.skinnyDipUndo(_:))
    static let redoSelector = #selector(EditorWebView.skinnyDipRedo(_:))
}
#endif

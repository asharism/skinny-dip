#if os(macOS)
import AppKit
import SwiftUI
import MarkdownCore

/// The Edit menu's pasteboard group (ADR-0011). ⌘C is the standard Copy: the
/// selected Markdown as plain text, disabled with no selection. ⌘⇧C Copy as Rich
/// Text and ⌥⌘C Copy as HTML copy the selection, or the whole document. With the
/// Preview focused, the commands copy its selection instead of the Editor's.
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
                NotificationCenter.default.post(name: .togglePreview, object: DocumentTabs.frontDocumentTab())
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        // Replacing the group drops the system Cut, Paste and friends too, so they
        // come back here as first-responder actions, which every text view handles.
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { send(#selector(NSText.cut(_:))) }
                .keyboardShortcut("x")
                .disabled(!(pasteboardMenuState?.canCut ?? true))
            Button("Copy", action: copy)
                .keyboardShortcut("c")
                .disabled(!(pasteboardMenuState?.canCopy ?? true))
            Button("Copy as Rich Text") { write(.richText) }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(source == nil || !(pasteboardMenuState?.canCopyRichText ?? true))
            Button("Copy as HTML") { write(.html) }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(source == nil || !(pasteboardMenuState?.canCopyRichText ?? true))
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
    private func copy() {
        guard source != nil else { return send(#selector(NSText.copy(_:))) }
        write(.plain)
    }

    private func write(_ command: CopyCommand) {
        if let preview = PreviewWebView.focused() {
            preview.copySelection(command)
            return
        }
        guard let source else { return }
        CopyWriter.write(command, markdown: source.markdown, selection: source.selection, documentID: source.documentID)
    }

    private func paste() {
        if let editor = EditorResponders.active() {
            editor.insertMarkdownFromPasteboard(plain: false)
        } else {
            send(#selector(NSText.paste(_:)))
        }
    }

    private func pasteAsPlainText() {
        if let editor = EditorResponders.active() {
            editor.insertMarkdownFromPasteboard(plain: true)
        } else {
            send(#selector(NSTextView.pasteAsPlainText(_:)))
        }
    }

    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    static let undoSelector = EditorResponders.undoSelector
    static let redoSelector = EditorResponders.redoSelector
}
#endif

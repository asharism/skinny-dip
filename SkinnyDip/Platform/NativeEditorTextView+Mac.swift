#if os(macOS)
import AppKit
import MarkdownCore

/// The native Editor Backend's text view: AppKit `NSTextView` on TextKit 2
/// (ADR-0010). Spell check, autocorrect, dictation and Writing Tools come from
/// AppKit. Copy and paste go through MarkdownCore like the CodeMirror backend:
/// never AppKit's own RTF copy, and ⌘V is Paste as Markdown.
final class NativeEditorTextView: NSTextView, EditorResponder {
    weak var editorCoordinator: NativeEditorView.Coordinator?
    /// Tests point this at a private pasteboard.
    var pasteboard: NSPasteboard = .general

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // A new Tab starts with the caret in the editor, as CodeMirror's does.
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            if window.firstResponder === window || window.firstResponder == nil {
                window.makeFirstResponder(self)
            }
        }
    }

    // MARK: EditorResponder

    func insertMarkdownFromPasteboard(plain: Bool) {
        let contents = pasteboard.pasteContents
        let text = plain ? PasteAsMarkdown.plainText(for: contents) : PasteAsMarkdown.text(for: contents)
        guard let text else { return }
        insertAsOneUndoStep(text)
    }

    @objc func skinnyDipUndo(_ sender: Any?) {
        undoManager?.undo()
    }

    @objc func skinnyDipRedo(_ sender: Any?) {
        undoManager?.redo()
    }

    /// AppKit hands Writing Tools the selection itself.
    func prepareWritingToolsSelection() async {}

    // MARK: Paste

    @objc override func paste(_ sender: Any?) {
        insertMarkdownFromPasteboard(plain: false)
    }

    @objc override func pasteAsPlainText(_ sender: Any?) {
        insertMarkdownFromPasteboard(plain: true)
    }

    @objc override func pasteAsRichText(_ sender: Any?) {
        insertMarkdownFromPasteboard(plain: false)
    }

    private func insertAsOneUndoStep(_ text: String) {
        breakUndoCoalescing()
        insertText(text, replacementRange: selectedRange())
        breakUndoCoalescing()
    }

    // MARK: Copy

    func copySource() -> (markdown: String, selection: Range<String.Index>?) {
        let markdown = string
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.count == 1, let range = ranges.first, range.length > 0 else { return (markdown, nil) }
        return (markdown, UTF16Selection.range(in: markdown, from: range.location, to: NSMaxRange(range)))
    }

    private var documentID: UUID? { editorCoordinator?.parent.documentID }

    @objc override func copy(_ sender: Any?) {
        let source = copySource()
        CopyWriter.writeRichText(markdown: source.markdown, selection: source.selection, documentID: documentID)
    }

    @objc override func cut(_ sender: Any?) {
        guard selectedRange().length > 0 else { return }
        copy(sender)
        delete(sender)
    }

    @objc func skinnyDipCopyMarkdown(_ sender: Any?) {
        let source = copySource()
        CopyWriter.writeMarkdown(markdown: source.markdown, selection: source.selection, documentID: documentID)
    }

    @objc func skinnyDipCopyHTML(_ sender: Any?) {
        let source = copySource()
        CopyWriter.writeHTML(markdown: source.markdown, selection: source.selection, documentID: documentID)
    }

    /// Drags and Services read the selection through here: the same Bare HTML
    /// plus Markdown as ⌘C, never AppKit's RTF.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let source = copySource()
        let payload = CopyWriter.richTextPayload(for: CopySource(markdown: source.markdown, selection: source.selection))
        MacClipboard(pasteboard: pboard).write(payload)
        return true
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.html, .string]
    }

    // MARK: Menus

    private var canCopy: Bool { selectedRange().length > 0 || !string.isEmpty }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(cut(_:)):
            return selectedRange().length > 0
        case #selector(copy(_:)), #selector(skinnyDipCopyMarkdown(_:)), #selector(skinnyDipCopyHTML(_:)):
            return canCopy
        case #selector(paste(_:)), #selector(pasteAsPlainText(_:)), #selector(pasteAsRichText(_:)):
            return pasteboard.canPasteFromPasteboard
        case EditorResponders.undoSelector:
            return undoManager?.canUndo ?? false
        case EditorResponders.redoSelector:
            return undoManager?.canRedo ?? false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        customizeCopyMenu(menu)
        NotificationCenter.default.post(name: .editorMenuWillOpen, object: nil)
        return menu
    }

    /// The context menu's Copy becomes the three copy commands, as in the CodeMirror backend.
    private func customizeCopyMenu(_ menu: NSMenu) {
        guard !menu.items.contains(where: { $0.action == #selector(skinnyDipCopyMarkdown(_:)) }),
              let copyIndex = menu.items.firstIndex(where: { $0.action == #selector(copy(_:)) })
        else { return }
        let copyItem = menu.items[copyIndex]
        copyItem.title = "Copy as Rich Text"
        copyItem.target = self

        let markdownItem = NSMenuItem(title: "Copy as Markdown", action: #selector(skinnyDipCopyMarkdown(_:)), keyEquivalent: "")
        markdownItem.target = self
        menu.insertItem(markdownItem, at: copyIndex + 1)

        let htmlItem = NSMenuItem(title: "Copy as HTML", action: #selector(skinnyDipCopyHTML(_:)), keyEquivalent: "")
        htmlItem.target = self
        menu.insertItem(htmlItem, at: copyIndex + 2)
    }
}
#endif

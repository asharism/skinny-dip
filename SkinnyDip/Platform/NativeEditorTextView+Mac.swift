#if os(macOS)
import AppKit
import MarkdownCore

/// The editor's text view: AppKit `NSTextView` on TextKit 2
/// (ADR-0010). Spell check, autocorrect, dictation and Writing Tools come from
/// AppKit. Copy and paste go through MarkdownCore:
/// never AppKit's own RTF copy, and ⌘V is Paste as Markdown.
final class NativeEditorTextView: NSTextView, EditorResponder {
    weak var editorCoordinator: NativeEditorView.Coordinator?
    /// Tests point this at a private pasteboard.
    var pasteboard: NSPasteboard = .general

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        // A new Tab starts with the caret in the editor.
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
        // A URL over a selection links it (#94); paste plain never does.
        if !plain, let url = MarkdownEditing.linkURL(in: contents), perform({ MarkdownEditing.pasteLink($0, url: url) }) { return }
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

    /// ⌘C (ADR-0011): the selected Markdown as plain text only; nothing with no selection.
    @objc override func copy(_ sender: Any?) {
        write(.plain)
    }

    /// ⌘X follows ⌘C, then deletes the selection as one undo step.
    @objc override func cut(_ sender: Any?) {
        guard selectedRange().length > 0, write(.plain) else { return }
        breakUndoCoalescing()
        delete(sender)
        breakUndoCoalescing()
    }

    @objc func skinnyDipCopyRichText(_ sender: Any?) {
        write(.richText)
    }

    @objc func skinnyDipCopyHTML(_ sender: Any?) {
        write(.html)
    }

    @discardableResult
    private func write(_ command: CopyCommand) -> Bool {
        let source = copySource()
        if command == .plain, source.selection == nil { return false }
        CopyWriter.write(command, markdown: source.markdown, selection: source.selection, documentID: documentID, clipboard: MacClipboard(pasteboard: pasteboard))
        return true
    }

    /// Drags and Services read the selection through here: the selected Markdown
    /// as plain text, like ⌘C, never AppKit's RTF.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let source = copySource()
        guard let selection = source.selection else { return false }
        MacClipboard(pasteboard: pboard).write(plainText: CopyAsMarkdown.text(for: source.markdown, selection: selection))
        return true
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }

    // MARK: Menus

    private var canCopyRichText: Bool { selectedRange().length > 0 || !string.isEmpty }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(cut(_:)), #selector(copy(_:)):
            return selectedRange().length > 0
        case #selector(skinnyDipCopyRichText(_:)), #selector(skinnyDipCopyHTML(_:)):
            return canCopyRichText
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

    /// The context menu's Copy stays the plain Copy, followed by Copy as Rich Text
    /// and Copy as HTML (ADR-0011).
    private func customizeCopyMenu(_ menu: NSMenu) {
        guard !menu.items.contains(where: { $0.action == #selector(skinnyDipCopyRichText(_:)) }),
              let copyIndex = menu.items.firstIndex(where: { $0.action == #selector(copy(_:)) })
        else { return }
        let copyItem = menu.items[copyIndex]
        copyItem.title = "Copy"
        copyItem.target = self

        let richItem = NSMenuItem(title: "Copy as Rich Text", action: #selector(skinnyDipCopyRichText(_:)), keyEquivalent: "")
        richItem.target = self
        menu.insertItem(richItem, at: copyIndex + 1)

        let htmlItem = NSMenuItem(title: "Copy as HTML", action: #selector(skinnyDipCopyHTML(_:)), keyEquivalent: "")
        htmlItem.target = self
        menu.insertItem(htmlItem, at: copyIndex + 2)
    }
}
#endif

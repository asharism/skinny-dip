#if os(macOS)
import AppKit
import MarkdownCore
import SwiftUI
import WebKit

/// CodeMirror 6 in a `WKWebView` (ADR-0003). Reports Markdown Source and selection to Swift; copy stays in MarkdownCore.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    @Binding var hasEditorSelection: Bool
    var documentID: UUID
    var themeVars: [String: String]
    var controller: EditorController

    private static let editDebounceNanoseconds: UInt64 = 200_000_000

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> EditorWebView {
        EditorTextCheckerDefaults.enable()
        let configuration = WKWebViewConfiguration()
        configuration.writingToolsBehavior = .complete
        configuration.allowsInlinePredictions = true
        configuration.userContentController.add(context.coordinator, name: "editor")

        let webView = EditorWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator
        webView.onSelectAll = { [weak webView] in
            Task { @MainActor in
                _ = try? await webView?.callAsyncJavaScript(
                    "return selectAllDocument()",
                    contentWorld: .page
                )
            }
        }
        webView.onUndo = { [weak webView] in
            Task { @MainActor in
                _ = try? await webView?.callAsyncJavaScript(
                    "return editorUndo()",
                    contentWorld: .page
                )
            }
        }
        webView.onRedo = { [weak webView] in
            Task { @MainActor in
                _ = try? await webView?.callAsyncJavaScript(
                    "return editorRedo()",
                    contentWorld: .page
                )
            }
        }
        webView.editorCoordinator = context.coordinator
        context.coordinator.webView = webView
        webView.useTransparentPage()
        context.coordinator.installBridge()
        #if DEBUG
        webView.isInspectable = true
        #endif

        guard let page = WebBundleResources.page(named: "editor.html"),
              let readAccess = WebBundleResources.readAccessRoot()
        else {
            return webView
        }
        webView.loadFileURL(page, allowingReadAccessTo: readAccess)
        return webView
    }

    func updateNSView(_ webView: EditorWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.installBridge()
        if context.coordinator.isReady {
            Task { @MainActor in await context.coordinator.applyThemeIfNeeded() }
        }
        if !context.coordinator.isReady {
            context.coordinator.pendingText = text
            return
        }
        guard text != context.coordinator.lastEditorText else { return }
        guard !context.coordinator.isApplyingRemoteEdit else { return }
        guard !context.coordinator.isBindingSyncPending else { return }
        Task { @MainActor in
            await context.coordinator.pushDocument(text, resetSelection: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EditorView
        weak var webView: EditorWebView?
        var isReady = false
        var jsBridgeReady = false
        var lastEditorText: String?
        var pendingText: String?
        var isApplyingRemoteEdit = false
        private(set)         var isBindingSyncPending = false
        private var debounceTask: Task<Void, Never>?
        private var appliedTheme: [String: String] = [:]

        init(parent: EditorView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.window?.makeFirstResponder(webView)
            Task { @MainActor in
                await finishLoadingIfNeeded()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
            #if DEBUG
            print("[SkinnyDip editor] navigation failed: \(error)")
            #endif
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            #if DEBUG
            print("[SkinnyDip editor] provisional navigation failed: \(error)")
            #endif
        }

        private func finishLoadingIfNeeded() async {
            guard !isReady, jsBridgeReady else { return }
            isReady = true
            let text = pendingText ?? parent.text
            pendingText = nil
            await pushDocument(text, resetSelection: true)
            await applyThemeIfNeeded()
            if let history = parent.controller.pendingHistory {
                parent.controller.pendingHistory = nil
                await importHistory(history)
            }
            webView?.window?.makeFirstResponder(webView)
            _ = try? await webView?.callAsyncJavaScript("return focusEditor()", contentWorld: .page)
            if let pending = pendingText, pending != lastEditorText {
                pendingText = nil
                await pushDocument(pending, resetSelection: true)
            }
        }

        /// The editor already shows `text` (a paste, or an immediate undo). Publish it
        /// to SwiftUI so the preview renders, without sending the text back into CodeMirror.
        func adoptEditorText(_ text: String) {
            lastEditorText = text
            debounceTask?.cancel()
            isBindingSyncPending = false
            if parent.text != text {
                parent.text = text
            }
        }

        func pushDocument(_ text: String, resetSelection: Bool) async {
            guard let webView else { return }
            isApplyingRemoteEdit = true
            defer { isApplyingRemoteEdit = false }
            do {
                _ = try await webView.callAsyncJavaScript(
                    "return setDocument(text)",
                    arguments: ["text": text],
                    contentWorld: .page
                )
                lastEditorText = text
                parent.canUndo = false
                parent.canRedo = false
                if resetSelection {
                    applySelection(from: 0, to: 0, rangeCount: 1)
                }
            } catch {
                #if DEBUG
                fputs("[SkinnyDip editor] setDocument failed: \(error)\n", stderr)
                #endif
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String
            else { return }

            switch event {
            case "editorReady":
                jsBridgeReady = true
                Task { @MainActor in
                    await finishLoadingIfNeeded()
                }
            case "documentChanged":
                guard let newText = body["text"] as? String else { return }
                lastEditorText = newText
                let immediate = body["immediate"] as? Bool ?? false
                debounceTask?.cancel()
                if immediate {
                    adoptEditorText(newText)
                    return
                }
                isBindingSyncPending = true
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: EditorView.editDebounceNanoseconds)
                    guard !Task.isCancelled else { return }
                    parent.text = newText
                    isBindingSyncPending = false
                }
            case "historyChanged":
                let canUndo = body["canUndo"] as? Bool ?? false
                let canRedo = body["canRedo"] as? Bool ?? false
                parent.canUndo = canUndo
                parent.canRedo = canRedo
            case "selectionChanged":
                let from = body["from"] as? Int ?? 0
                let to = body["to"] as? Int ?? 0
                let rangeCount = body["rangeCount"] as? Int ?? 1
                if let hasSelection = body["hasSelection"] as? Bool {
                    parent.hasEditorSelection = hasSelection
                }
                if let head = body["head"] as? Int {
                    parent.controller.cursorUTF16 = head
                } else {
                    parent.controller.cursorUTF16 = from
                }
                applySelection(from: from, to: to, rangeCount: rangeCount)
            case "viewport":
                let line = Self.number(body["topLine"])
                let fraction = Self.number(body["fraction"])
                parent.controller.viewport = EditorViewport(topLine: Int(line ?? 1), fraction: fraction ?? 0)
            case "historyRestoreFailed":
                break
            default:
                break
            }
        }

        func installBridge() {
            guard let webView else { return }
            parent.controller.exportState = { [weak webView] in
                guard let webView else { return nil }
                let result = try? await webView.callAsyncJavaScript("return exportState()", contentWorld: .page)
                return result as? String
            }
            parent.controller.importState = { [weak webView] json in
                _ = try? await webView?.callAsyncJavaScript(
                    "return importState(json)",
                    arguments: ["json": json],
                    contentWorld: .page
                )
            }
        }

        func applyThemeIfNeeded() async {
            guard let webView, parent.themeVars != appliedTheme else { return }
            appliedTheme = parent.themeVars
            _ = try? await webView.callAsyncJavaScript(
                "return setTheme(vars)",
                arguments: ["vars": parent.themeVars],
                contentWorld: .page
            )
        }

        func importHistory(_ json: String) async {
            guard let webView else { return }
            _ = try? await webView.callAsyncJavaScript(
                "return importState(json)",
                arguments: ["json": json],
                contentWorld: .page
            )
        }

        private static func number(_ value: Any?) -> Double? {
            switch value {
            case let number as Double: return number
            case let number as Int: return Double(number)
            case let number as NSNumber: return number.doubleValue
            default: return nil
            }
        }

        private func applySelection(from: Int, to: Int, rangeCount: Int) {
            let markdown = lastEditorText ?? parent.text
            guard rangeCount == 1,
                  let range = UTF16Selection.range(in: markdown, from: from, to: to),
                  !range.isEmpty
            else {
                parent.selection = nil
                return
            }
            parent.selection = range
        }
    }
}

/// Edit menu Select All must reach CodeMirror, not WebKit's viewport-limited default.
final class EditorWebView: WKWebView {
    override var isOpaque: Bool { false }

    func useTransparentPage() {
        underPageBackgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    var onSelectAll: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    weak var editorCoordinator: EditorView.Coordinator?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            Task { @MainActor in
                _ = try? await callAsyncJavaScript("return focusEditor()", contentWorld: .page)
            }
        }
        return became
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .textArea
    }

    @MainActor
    func prepareWritingToolsSelection() async {
        _ = try? await callAsyncJavaScript(
            "return ensureWritingToolsSelection()",
            contentWorld: .page
        )
    }

    @objc func openWritingTools(_ sender: Any?) {
        Task { @MainActor in
            await prepareWritingToolsSelection()
            guard responds(to: AppWritingTools.webKitAction) else { return }
            _ = perform(AppWritingTools.webKitAction, with: sender)
        }
    }

    override func selectAll(_ sender: Any?) {
        if let onSelectAll {
            onSelectAll()
        } else {
            super.selectAll(sender)
        }
    }

    @objc func copy(_ sender: Any?) {
        writeRichTextToPasteboard()
    }

    @objc func cut(_ sender: Any?) {
        writeRichTextToPasteboard()
        Task { @MainActor in
            _ = try? await callAsyncJavaScript("return editorCut()", contentWorld: .page)
        }
    }

    /// The editor web view in the key window, when ⌘V should land in the document
    /// rather than in another text field (Settings, an open panel).
    static func pasteTarget() -> EditorWebView? {
        if let editor = enclosingEditor(NSApp.keyWindow?.firstResponder) { return editor }
        if NSApp.keyWindow?.firstResponder is NSTextView { return nil }
        return editorWebView(in: NSApp.keyWindow?.contentView)
    }

    private static func enclosingEditor(_ responder: NSResponder?) -> EditorWebView? {
        var current = responder
        while let next = current {
            if let editor = next as? EditorWebView { return editor }
            current = next.nextResponder
        }
        return nil
    }

    private static func editorWebView(in view: NSView?) -> EditorWebView? {
        guard let view else { return nil }
        if let editor = view as? EditorWebView { return editor }
        for child in view.subviews {
            if let editor = editorWebView(in: child) { return editor }
        }
        return nil
    }

    /// Tests point this at a private pasteboard.
    var pasteboard: NSPasteboard = .general

    /// Paste as Markdown. WebKit's own paste reads the pasteboard in the web
    /// process, which the sandbox blocks, so ⌘V resolves the text here
    /// (`PasteAsMarkdown`) and pushes it in over the bridge.
    @objc func paste(_ sender: Any?) {
        guard let text = PasteAsMarkdown.text(for: pasteboard.pasteContents) else { return }
        insertEditorText(text)
    }

    /// Paste and Match Style: the plain-text flavor, never converted.
    @objc func pasteAsPlainText(_ sender: Any?) {
        guard let text = PasteAsMarkdown.plainText(for: pasteboard.pasteContents) else { return }
        insertEditorText(text)
    }

    private var lastInsertedPaste: (text: String, at: Date)?

    private func insertEditorText(_ text: String) {
        // ⌘V is delivered both by the key monitor and the Edit menu. Keep one insert.
        if let last = lastInsertedPaste, last.text == text, Date().timeIntervalSince(last.at) < 0.2 {
            return
        }
        lastInsertedPaste = (text, Date())
        Task { @MainActor in
            let inserted = try? await callAsyncJavaScript(
                "return insertText(text)",
                arguments: ["text": text],
                contentWorld: .page
            )
            if let inserted = inserted as? String {
                editorCoordinator?.adoptEditorText(inserted)
            }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if AppKeyboardShortcuts.performMainMenuShortcut(event) {
            return true
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Returning false drops the event: AppKit already consumed it as a
        // key-equivalent search, so CodeMirror never sees ⌃A/E/K or ⌃⇧↑/↓.
        if event.type == .keyDown, flags.contains(.control), !flags.contains(.command) {
            keyDown(with: event)
            return true
        }
        guard event.type == .keyDown, event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return super.performKeyEquivalent(with: event)
        }
        if flags.contains(.shift) {
            writeMarkdownToPasteboard()
            return true
        }
        if flags.contains(.option) {
            writeHTMLToPasteboard()
            return true
        }
        copy(nil)
        return true
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        AppWritingTools.ensureWritingTools(menu: menu, target: self)
        NotificationCenter.default.post(name: .editorMenuWillOpen, object: nil)
        customizeCopyMenu(menu)
        validateContextMenuPasteboardItems(menu)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(cut(_:)):
            let enabled = editorCanCut
            (item as? NSMenuItem)?.isEnabled = enabled
            return enabled
        case #selector(copy(_:)):
            let enabled = editorCanCopy
            (item as? NSMenuItem)?.isEnabled = enabled
            return enabled
        case #selector(paste(_:)):
            let enabled = pasteboard.canPasteFromPasteboard
            (item as? NSMenuItem)?.isEnabled = enabled
            return enabled
        default:
            break
        }
        return super.validateUserInterfaceItem(item)
    }

    private var editorCanCut: Bool {
        guard let coordinator = editorCoordinator else { return false }
        return coordinator.parent.hasEditorSelection
    }

    private var editorCanCopy: Bool {
        guard let coordinator = editorCoordinator else { return false }
        let markdown = coordinator.lastEditorText ?? coordinator.parent.text
        return coordinator.parent.hasEditorSelection || !markdown.isEmpty
    }

    private func validateContextMenuPasteboardItems(_ menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(cut(_:)):
                item.isEnabled = editorCanCut
            case #selector(copy(_:)), #selector(NSText.copy(_:)):
                item.isEnabled = editorCanCopy
            case #selector(paste(_:)):
                item.isEnabled = pasteboard.canPasteFromPasteboard
            default:
                break
            }
        }
    }

    @objc func skinnyDipUndo(_ sender: Any?) {
        onUndo?()
    }

    @objc func skinnyDipRedo(_ sender: Any?) {
        onRedo?()
    }

    @objc func skinyDipCopyMarkdown(_ sender: Any?) {
        writeMarkdownToPasteboard()
    }

    @objc func skinyDipCopyHTML(_ sender: Any?) {
        writeHTMLToPasteboard()
    }

    private func copySource() -> (markdown: String, selection: Range<String.Index>?) {
        guard let coordinator = editorCoordinator else { return ("", nil) }
        let markdown = coordinator.lastEditorText ?? coordinator.parent.text
        return (markdown, coordinator.parent.selection)
    }

    private func writeRichTextToPasteboard() {
        let source = copySource()
        CopyWriter.writeRichText(markdown: source.markdown, selection: source.selection, documentID: editorCoordinator?.parent.documentID)
    }

    private func writeMarkdownToPasteboard() {
        let source = copySource()
        CopyWriter.writeMarkdown(markdown: source.markdown, selection: source.selection, documentID: editorCoordinator?.parent.documentID)
    }

    private func writeHTMLToPasteboard() {
        let source = copySource()
        CopyWriter.writeHTML(markdown: source.markdown, selection: source.selection, documentID: editorCoordinator?.parent.documentID)
    }

    private func customizeCopyMenu(_ menu: NSMenu) {
        guard let copyIndex = menu.items.firstIndex(where: { isCopyMenuItem($0) }) else { return }
        let copyItem = menu.items[copyIndex]
        copyItem.title = "Copy as Rich Text"
        copyItem.target = self
        copyItem.action = #selector(copy(_:))

        let markdownItem = NSMenuItem(
            title: "Copy as Markdown",
            action: #selector(skinyDipCopyMarkdown(_:)),
            keyEquivalent: ""
        )
        markdownItem.target = self
        menu.insertItem(markdownItem, at: copyIndex + 1)

        let htmlItem = NSMenuItem(
            title: "Copy as HTML",
            action: #selector(skinyDipCopyHTML(_:)),
            keyEquivalent: ""
        )
        htmlItem.target = self
        menu.insertItem(htmlItem, at: copyIndex + 2)
    }

    private func isCopyMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(copy(_:))
            || item.action == #selector(NSText.copy(_:))
            || item.title == "Copy"
    }
}
#endif

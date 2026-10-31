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

    private static let editDebounceNanoseconds: UInt64 = 200_000_000

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> EditorWebView {
        let configuration = WKWebViewConfiguration()
        configuration.writingToolsBehavior = .complete
        configuration.userContentController.add(context.coordinator, name: "editor")

        let webView = EditorWebView(frame: .zero, configuration: configuration)
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

        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("Resources"),
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("editor.html").path)
        else {
            return webView
        }
        let page = resources.appendingPathComponent("editor.html")
        webView.loadFileURL(page, allowingReadAccessTo: resources)
        return webView
    }

    func updateNSView(_ webView: EditorWebView, context: Context) {
        context.coordinator.parent = self
        guard context.coordinator.isReady else { return }
        guard text != context.coordinator.lastEditorText else { return }
        guard !context.coordinator.isApplyingRemoteEdit else { return }
        Task { @MainActor in
            await context.coordinator.pushDocument(text)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EditorView
        weak var webView: EditorWebView?
        var isReady = false
        var lastEditorText: String?
        var isApplyingRemoteEdit = false
        private var debounceTask: Task<Void, Never>?

        init(parent: EditorView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.window?.makeFirstResponder(webView)
            Task { @MainActor in
                await pushDocument(parent.text)
                isReady = true
            }
        }

        func pushDocument(_ text: String) async {
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
                applySelection(from: 0, to: 0, rangeCount: 1)
            } catch {
                // WebKit failed; binding still holds the Markdown Source.
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let event = body["event"] as? String
            else { return }

            switch event {
            case "documentChanged":
                guard let newText = body["text"] as? String else { return }
                lastEditorText = newText
                let immediate = body["immediate"] as? Bool ?? false
                debounceTask?.cancel()
                if immediate {
                    parent.text = newText
                    return
                }
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: EditorView.editDebounceNanoseconds)
                    guard !Task.isCancelled else { return }
                    parent.text = newText
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
                applySelection(from: from, to: to, rangeCount: rangeCount)
            default:
                break
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
    var onSelectAll: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    weak var editorCoordinator: EditorView.Coordinator?

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

    @objc func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if let markdown = pasteboard.string(forType: .skinnyDipMarkdown), !markdown.isEmpty {
            Task { @MainActor in
                _ = try? await callAsyncJavaScript(
                    "return insertText(text)",
                    arguments: ["text": markdown],
                    contentWorld: .page
                )
            }
            return
        }
        if let next = nextResponder, next.responds(to: #selector(paste(_:))) {
            next.perform(#selector(paste(_:)), with: sender)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
        customizeCopyMenu(menu)
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
        CopyWriter.writeRichText(markdown: source.markdown, selection: source.selection)
    }

    private func writeMarkdownToPasteboard() {
        let source = copySource()
        CopyWriter.writeMarkdown(markdown: source.markdown, selection: source.selection)
    }

    private func writeHTMLToPasteboard() {
        let source = copySource()
        CopyWriter.writeHTML(markdown: source.markdown, selection: source.selection)
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

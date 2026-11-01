#if os(macOS)
import MarkdownCore
import SwiftUI
import WebKit

/// CodeMirror 6 in a `WKWebView` (ADR-0003). Reports Markdown Source and selection to Swift; copy stays in MarkdownCore.
struct EditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?

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
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: EditorView.editDebounceNanoseconds)
                    guard !Task.isCancelled else { return }
                    parent.text = newText
                }
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

/// Select All from the Edit menu must reach CodeMirror, not WebKit's viewport-limited default.
final class EditorWebView: WKWebView {
    var onSelectAll: (() -> Void)?

    override func selectAll(_ sender: Any?) {
        if let onSelectAll {
            onSelectAll()
        } else {
            super.selectAll(sender)
        }
    }
}
#endif

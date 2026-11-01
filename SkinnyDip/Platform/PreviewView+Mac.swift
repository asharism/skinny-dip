#if os(macOS)
import AppKit
import MarkdownCore
import SwiftUI
import WebKit

/// Live Preview in its own `WKWebView` (ADR-0004). Loads `preview.html` once, then
/// pushes HTML via JS `render(html)` so scroll position is kept across updates.
struct PreviewView: NSViewRepresentable {
    let html: String
    let markdown: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PreviewWebView {
        let configuration = WKWebViewConfiguration()
        let webView = PreviewWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("Resources"),
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("preview.html").path)
        else {
            return webView
        }
        let page = resources.appendingPathComponent("preview.html")
        webView.loadFileURL(page, allowingReadAccessTo: resources)
        return webView
    }

    func updateNSView(_ webView: PreviewWebView, context: Context) {
        webView.markdown = markdown
        context.coordinator.parentHTML = html
        guard context.coordinator.isReady else { return }
        guard html != context.coordinator.lastHTML else { return }
        Task { @MainActor in
            await context.coordinator.pushHTML(html)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: PreviewWebView?
        var isReady = false
        var lastHTML: String?
        var parentHTML = ""

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            Task { @MainActor in
                await pushHTML(parentHTML)
            }
        }

        func pushHTML(_ html: String) async {
            guard let webView else { return }
            lastHTML = html
            do {
                _ = try await webView.callAsyncJavaScript(
                    "render(html)",
                    arguments: ["html": html],
                    contentWorld: .page
                )
            } catch {
                // WebKit failed; the next edit will retry.
            }
        }
    }
}

/// ⌘C copies the whole document via CopyWriter, never WebKit's themed HTML.
final class PreviewWebView: WKWebView {
    var markdown = ""

    @objc func copy(_ sender: Any?) {
        CopyWriter.writeRichText(markdown: markdown, selection: nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            CopyWriter.writeMarkdown(markdown: markdown, selection: nil)
            return true
        }
        if flags.contains(.option) {
            CopyWriter.writeHTML(markdown: markdown, selection: nil)
            return true
        }
        copy(nil)
        return true
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let copyIndex = menu.items.firstIndex(where: { isCopyMenuItem($0) }) else { return }
        let copyItem = menu.items[copyIndex]
        copyItem.title = "Copy as Rich Text"
        copyItem.target = self
        copyItem.action = #selector(copy(_:))
    }

    private func isCopyMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(copy(_:))
            || item.action == #selector(NSText.copy(_:))
            || item.title == "Copy"
    }
}
#endif

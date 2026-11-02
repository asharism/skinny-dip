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
    var documentID: UUID
    var themeVars: [String: String]
    var zoom: Double
    var scrollSync: Bool
    var syncActive: Bool
    var viewport: EditorViewport

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PreviewWebView {
        let configuration = WKWebViewConfiguration()
        let webView = PreviewWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = context.coordinator
        webView.useTransparentPage()
        context.coordinator.webView = webView

        guard let page = WebBundleResources.page(named: "preview.html") else {
            return webView
        }
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: PreviewWebView, context: Context) {
        webView.markdown = markdown
        webView.documentID = documentID
        context.coordinator.parentHTML = html
        context.coordinator.themeVars = themeVars
        context.coordinator.zoom = zoom
        context.coordinator.scrollSync = scrollSync
        context.coordinator.syncActive = syncActive
        context.coordinator.viewport = viewport
        guard context.coordinator.isReady else { return }
        Task { @MainActor in
            await context.coordinator.pushChrome()
            if html != context.coordinator.lastHTML {
                await context.coordinator.pushHTML(html)
            } else if syncActive {
                await context.coordinator.syncViewport()
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: PreviewWebView?
        var isReady = false
        var lastHTML: String?
        var parentHTML = ""
        var themeVars: [String: String] = [:]
        var zoom = 1.0
        var scrollSync = true
        var syncActive = true
        var viewport = EditorViewport(topLine: 1, fraction: 0)
        private var appliedTheme: [String: String] = [:]
        private var appliedZoom = -1.0
        private var appliedSync: Bool?
        private var syncInFlight = false
        private var pendingViewport: EditorViewport?
        private var queuedHTML: String?
        private var renderInFlight = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            Task { @MainActor in
                await pushChrome()
                await pushHTML(parentHTML)
            }
        }

        func pushChrome() async {
            guard let webView else { return }
            if themeVars != appliedTheme {
                appliedTheme = themeVars
                _ = try? await webView.callAsyncJavaScript(
                    "setTheme(vars)",
                    arguments: ["vars": themeVars],
                    contentWorld: .page
                )
            }
            if zoom != appliedZoom {
                appliedZoom = zoom
                _ = try? await webView.callAsyncJavaScript(
                    "setZoom(zoom)",
                    arguments: ["zoom": zoom],
                    contentWorld: .page
                )
            }
            if appliedSync != scrollSync {
                appliedSync = scrollSync
                _ = try? await webView.callAsyncJavaScript(
                    "setScrollSync(on)",
                    arguments: ["on": scrollSync],
                    contentWorld: .page
                )
            }
        }

        func pushHTML(_ html: String) async {
            // Overlapping renders finish out of order: an older body can land
            // after the paste and leave the preview on the previous document.
            queuedHTML = html
            guard !renderInFlight else { return }
            renderInFlight = true
            defer { renderInFlight = false }
            while let next = queuedHTML {
                queuedHTML = nil
                guard let webView else { return }
                let line = viewport.topLine
                let fraction = Self.jsNumber(viewport.fraction)
                do {
                    _ = try await webView.callAsyncJavaScript(
                        "return render(html, \(line), \(fraction))",
                        arguments: ["html": next],
                        contentWorld: .page
                    )
                    lastHTML = next
                } catch {
                    // Leave lastHTML unchanged so the next update tries again.
                }
            }
        }

        func syncViewport() async {
            guard syncActive else { return }
            pendingViewport = viewport
            guard !syncInFlight else { return }
            syncInFlight = true
            defer { syncInFlight = false }
            while let next = pendingViewport {
                pendingViewport = nil
                guard let webView else { return }
                let line = next.topLine
                let fraction = Self.jsNumber(next.fraction)
                _ = try? await webView.callAsyncJavaScript(
                    "return syncToLine(\(line), \(fraction))",
                    contentWorld: .page
                )
            }
        }

        private static func jsNumber(_ value: Double) -> String {
            String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
        }
    }
}

/// ⌘C copies the whole document via CopyWriter, never WebKit's themed HTML.
final class PreviewWebView: WKWebView {
    override var isOpaque: Bool { false }

    func useTransparentPage() {
        underPageBackgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    var markdown = ""
    var documentID: UUID?

    @objc func copy(_ sender: Any?) {
        CopyWriter.writeRichText(markdown: markdown, selection: nil, documentID: documentID)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if AppKeyboardShortcuts.performMainMenuShortcut(event) {
            return true
        }
        guard event.type == .keyDown, event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            CopyWriter.writeMarkdown(markdown: markdown, selection: nil, documentID: documentID)
            return true
        }
        if flags.contains(.option) {
            CopyWriter.writeHTML(markdown: markdown, selection: nil, documentID: documentID)
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

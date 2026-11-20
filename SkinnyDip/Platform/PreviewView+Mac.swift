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
    /// The `data-source-line` of the block the Editor's caret is in, tinted in the Preview.
    var highlightLine: Int? = nil
    /// Nil while the Preview doesn't have focus, otherwise whether it has a selection.
    var onCopyStateChange: ((Bool?) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PreviewWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "previewSelection")
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
        webView.onCopyStateChange = onCopyStateChange
        context.coordinator.parentHTML = html
        context.coordinator.themeVars = themeVars
        context.coordinator.zoom = zoom
        context.coordinator.scrollSync = scrollSync
        context.coordinator.syncActive = syncActive
        context.coordinator.viewport = viewport
        context.coordinator.highlightLine = highlightLine
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
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var webView: PreviewWebView?
        var isReady = false
        var lastHTML: String?
        var parentHTML = ""
        var themeVars: [String: String] = [:]
        var zoom = 1.0
        var scrollSync = true
        var syncActive = true
        var viewport = EditorViewport(topLine: 1, fraction: 0)
        var highlightLine: Int?
        private var appliedHighlight: Int??
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

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "previewSelection", let hasSelection = message.body as? Bool else { return }
            webView?.pageSelectionChanged(hasSelection)
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
            if appliedHighlight != .some(highlightLine) {
                appliedHighlight = .some(highlightLine)
                _ = try? await webView.callAsyncJavaScript(
                    "highlightBlock(line)",
                    arguments: ["line": highlightLine.map { $0 as Any } ?? NSNull()],
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

/// Copies through CopyWriter, never WebKit's themed HTML, with the Editor's keys
/// (ADR-0011). A selection maps back to the Markdown Source of the blocks it
/// touches (`PreviewSelection`). ⌘C copies that Markdown as plain text and does
/// nothing with no selection; ⌘⇧C copies it as rich text and ⌥⌘C as HTML, both
/// falling back to the whole document when nothing is selected.
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
    /// Tests point this at a private pasteboard.
    var pasteboard: NSPasteboard = .general
    /// Nil while the Preview doesn't have focus, otherwise whether the page has a
    /// selection. Feeds the Edit menu's Copy state.
    var onCopyStateChange: ((Bool?) -> Void)?
    private var pageHasSelection = false

    /// The Preview in the key window that has keyboard focus, if any.
    static func focused() -> PreviewWebView? {
        var view = NSApp.keyWindow?.firstResponder as? NSView
        while let current = view {
            if let preview = current as? PreviewWebView { return preview }
            view = current.superview
        }
        return nil
    }

    private var isFocused: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: self)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onCopyStateChange?(pageHasSelection) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onCopyStateChange?(nil) }
        return resigned
    }

    /// Hiding the Preview Card takes it out of the window without resigning.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { onCopyStateChange?(nil) }
    }

    /// The page reports `selectionchange` through the `previewSelection` message handler.
    func pageSelectionChanged(_ hasSelection: Bool) {
        pageHasSelection = hasSelection
        if isFocused { onCopyStateChange?(hasSelection) }
    }

    @objc func copy(_ sender: Any?) {
        copySelection(.plain)
    }

    @objc func skinnyDipCopyRichText(_ sender: Any?) {
        copySelection(.richText)
    }

    /// Reads the selection from the page, then writes with the Markdown and document
    /// captured now, so a render landing in between can't change what is copied.
    @discardableResult
    func copySelection(_ command: CopyCommand) -> Task<Void, Never> {
        let markdown = markdown, documentID = documentID, pasteboard = pasteboard
        return Task { @MainActor in
            let selection = await selectedSourceRange(in: markdown)
            CopyWriter.write(
                command,
                markdown: markdown,
                selection: selection,
                documentID: documentID,
                clipboard: MacClipboard(pasteboard: pasteboard)
            )
        }
    }

    /// Nil when nothing is selected or the page can't be read.
    func selectedSourceRange(in markdown: String) async -> Range<String.Index>? {
        guard let lines = try? await callAsyncJavaScript("return selectedSourceLines()", contentWorld: .page) as? [Int],
              lines.count == 2
        else { return nil }
        return PreviewSelection.range(in: markdown, firstBlockLine: lines[0], lastBlockLine: lines[1])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if AppKeyboardShortcuts.performMainMenuShortcut(event) {
            return true
        }
        if AppKeyboardShortcuts.isHelpSearch(event) {
            return false
        }
        // Only the focused Preview answers ⌘C; otherwise the Editor's copy runs.
        guard isFocused, event.type == .keyDown, event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return super.performKeyEquivalent(with: event)
        }
        // Any other ⌘…C is swallowed so WebKit's styled copy never runs.
        if let command = AppKeyboardShortcuts.copyCommand(for: event) {
            copySelection(command)
        }
        return true
    }

    /// WebKit's Copy becomes the plain Copy, followed by Copy as Rich Text.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard !menu.items.contains(where: { $0.action == #selector(skinnyDipCopyRichText(_:)) }),
              let copyIndex = menu.items.firstIndex(where: { isCopyMenuItem($0) })
        else { return }
        let copyItem = menu.items[copyIndex]
        copyItem.title = "Copy"
        copyItem.target = self
        copyItem.action = #selector(copy(_:))

        let richItem = NSMenuItem(title: "Copy as Rich Text", action: #selector(skinnyDipCopyRichText(_:)), keyEquivalent: "")
        richItem.target = self
        menu.insertItem(richItem, at: copyIndex + 1)
    }

    private func isCopyMenuItem(_ item: NSMenuItem) -> Bool {
        item.action == #selector(copy(_:))
            || item.action == #selector(NSText.copy(_:))
            || item.title == "Copy"
    }
}
#endif

#if os(macOS)
import AppKit
import MarkdownCore
import WebKit

/// Print (⌘P): renders the whole document into an off-screen copy of the
/// Preview page and hands it to the system print panel. The live Preview is
/// never touched, so a hidden Preview Card, its scroll, Theme and Zoom don't
/// matter; `theme.css` gives the page its paper style under `@media print`.
@MainActor
final class PreviewPrinter: NSObject, WKNavigationDelegate, WKUIDelegate {
    enum Failure: Error { case missingPage }

    /// How long Print waits for remote images before printing what it has.
    static let imageTimeout: TimeInterval = 3

    /// Printers in flight; each removes itself when its print panel closes.
    private static var active: [ObjectIdentifier: PreviewPrinter] = [:]

    let webView: WKWebView
    /// Header text on every printed page (the Tab title).
    var title = ""
    private var loaded: CheckedContinuation<Void, Error>?

    init(pageWidth: CGFloat) {
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: max(pageWidth, 320), height: 800),
            configuration: WKWebViewConfiguration()
        )
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    static func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = false
        if info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] == nil {
            info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true
        }
        return info
    }

    /// Prints the whole document through the system print panel, as a sheet on `window`.
    static func print(markdown: String, options: RenderOptions, title: String, window: NSWindow) {
        let info = printInfo()
        let printer = PreviewPrinter(pageWidth: info.imageablePageBounds.width)
        active[ObjectIdentifier(printer)] = printer
        let html = PreviewHTML.render(markdown, options: options)
        Task { @MainActor in
            do {
                try await printer.load(html: html)
            } catch {
                active[ObjectIdentifier(printer)] = nil
                NSSound.beep()
                return
            }
            let operation = printer.operation(printInfo: info, title: title)
            operation.runModal(
                for: window,
                delegate: printer,
                didRun: #selector(PreviewPrinter.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
    }

    /// Loads `preview.html`, renders `html` without scroll sync, and waits for images.
    func load(html: String, imageTimeout: TimeInterval = PreviewPrinter.imageTimeout) async throws {
        guard let page = WebBundleResources.page(named: "preview.html") else { throw Failure.missingPage }
        let access = WebBundleResources.readAccessRoot() ?? page.deletingLastPathComponent()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loaded = continuation
            webView.loadFileURL(page, allowingReadAccessTo: access)
        }
        _ = try await webView.callAsyncJavaScript(
            "setScrollSync(false); render(html); return await whenImagesLoaded(ms);",
            arguments: ["html": html, "ms": imageTimeout * 1000],
            contentWorld: .page
        )
    }

    func operation(printInfo: NSPrintInfo, title: String) -> NSPrintOperation {
        self.title = title
        let operation = webView.printOperation(with: printInfo)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.addAccessoryController(HeaderFooterAccessory())
        // WKWebView's print view starts at zero size and prints blank pages otherwise.
        operation.view?.frame = webView.bounds
        return operation
    }

    /// AppKit can finish the operation on its own print thread, not main.
    @objc nonisolated private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let key = ObjectIdentifier(self)
        Task { @MainActor in Self.active[key] = nil }
    }

    // MARK: Header and footer
    //
    // WKWebView ignores AppKit's `headerAndFooter` print setting. These are
    // WebKit's private WKUIDelegate print callbacks (what Safari uses): if a
    // future WebKit drops them, pages simply print without header and footer.

    private static let marginTextHeight: CGFloat = 24
    private static var marginAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor(white: 0.35, alpha: 1)]
    }

    /// The panel's "Print header and footer" checkbox, or on by default.
    private var showsHeaderAndFooter: Bool {
        let info = NSPrintOperation.current?.printInfo
        return (info?.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] as? Bool) ?? true
    }

    @objc(_webViewHeaderHeight:)
    func printHeaderHeight(_ webView: WKWebView) -> CGFloat {
        showsHeaderAndFooter ? Self.marginTextHeight : 0
    }

    @objc(_webViewFooterHeight:)
    func printFooterHeight(_ webView: WKWebView) -> CGFloat {
        showsHeaderAndFooter ? Self.marginTextHeight : 0
    }

    @objc(_webView:drawHeaderInRect:forPageWithTitle:URL:)
    func drawPrintHeader(_ webView: WKWebView, rect: NSRect, pageTitle: String?, url: URL?) {
        guard showsHeaderAndFooter else { return }
        Self.draw(title, centeredIn: rect)
    }

    @objc(_webView:drawFooterInRect:forPageWithTitle:URL:)
    func drawPrintFooter(_ webView: WKWebView, rect: NSRect, pageTitle: String?, url: URL?) {
        guard showsHeaderAndFooter, let operation = NSPrintOperation.current else { return }
        let page = operation.currentPage
        let total = operation.pageRange.length
        Self.draw(total > 0 ? "\(page) of \(total)" : "\(page)", centeredIn: rect)
    }

    private static func draw(_ text: String, centeredIn rect: NSRect) {
        let string = NSAttributedString(string: text, attributes: marginAttributes)
        let size = string.size()
        let origin = NSPoint(
            x: rect.midX - min(size.width, rect.width) / 2,
            y: rect.midY - size.height / 2
        )
        string.draw(with: NSRect(origin: origin, size: NSSize(width: min(size.width, rect.width), height: size.height)),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume()
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(throwing: error)
        loaded = nil
    }
}
/// The "Print header and footer" checkbox in the print panel; WKWebView's
/// print view doesn't get AppKit's own one.
final class HeaderFooterAccessory: NSViewController, NSPrintPanelAccessorizing {
    private let checkbox = NSButton(checkboxWithTitle: "Print header and footer", target: nil, action: nil)

    override func loadView() {
        checkbox.target = self
        checkbox.action = #selector(toggle(_:))
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 32))
        checkbox.frame = NSRect(x: 0, y: 6, width: 260, height: 20)
        container.addSubview(checkbox)
        view = container
    }

    override var representedObject: Any? {
        didSet { checkbox.state = isOn ? .on : .off }
    }

    private var info: NSPrintInfo? { representedObject as? NSPrintInfo }

    @objc dynamic var isOn: Bool {
        get { (info?.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] as? Bool) ?? true }
        set { info?.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = newValue }
    }

    @objc private func toggle(_ sender: NSButton) {
        isOn = sender.state == .on
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [[.itemName: "Header and Footer", .itemDescription: isOn ? "On" : "Off"]]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["isOn"]
    }
}
#endif

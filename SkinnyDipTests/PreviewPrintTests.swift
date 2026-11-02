#if os(macOS)
import AppKit
import PDFKit
import Testing
import WebKit
import MarkdownCore
@testable import SkinnyDip

/// Print (⌘P): the off-screen Preview page, its paper style and its pagination.
@MainActor
struct PreviewPrintTests {
    private static let longDocument = (1...120)
        .map { "## Section \($0)\n\nParagraph \($0) of the printed document." }
        .joined(separator: "\n\n") + "\n\nThe very last line."

    @Test func printStyleIgnoresThemeAndZoom() async throws {
        let printer = PreviewPrinter(pageWidth: 540)
        try await printer.load(html: PreviewHTML.render("# Title\n\nBody text."))
        // A dark Theme and 200% Zoom, the way the live Preview gets them.
        _ = try await printer.webView.callAsyncJavaScript(
            "setTheme(vars); setZoom(2);",
            arguments: ["vars": ["--fg": "#eeeeee", "--heading": "#ffcc88"]],
            contentWorld: .page
        )
        printer.webView.mediaType = "print"
        let style = try await printer.webView.callAsyncJavaScript(
            """
            const h = getComputedStyle(document.querySelector("h1, h2"));
            const p = getComputedStyle(document.querySelector("p"));
            const html = getComputedStyle(document.documentElement);
            const body = getComputedStyle(document.body);
            return [h.color, p.color, html.fontSize, body.overflowY, body.height === html.height ? "fixed" : "auto"];
            """,
            contentWorld: .page
        ) as? [String]
        let values = try #require(style)
        #expect(values[0] == "rgb(0, 0, 0)")
        #expect(values[1] == "rgb(0, 0, 0)")
        #expect(values[2].hasPrefix("14.66"))  // 11pt, not 13px × Zoom
        #expect(values[3] == "visible")
    }

    @Test func longDocumentPrintsEveryPage() async throws {
        let pdf = try await Self.printToPDF(Self.longDocument, title: "Long Notes.md")
        #expect(pdf.pageCount > 3)
        let text = pdf.string ?? ""
        #expect(text.contains("Section 1"))
        #expect(text.contains("The very last line."))
        #expect(!text.contains("Your formatted text appears here."))
        // Header (Tab title) and footer (page numbers) on every page.
        let second = pdf.page(at: 1)?.string ?? ""
        #expect(second.contains("Long Notes.md"))
        #expect(second.contains("2 of \(pdf.pageCount)"))
    }

    @Test func headerAndFooterCanBeTurnedOff() async throws {
        let pdf = try await Self.printToPDF(Self.longDocument, title: "Long Notes.md", headerAndFooter: false)
        let second = pdf.page(at: 1)?.string ?? ""
        #expect(!second.contains("Long Notes.md"))
        #expect(!second.contains("2 of \(pdf.pageCount)"))
    }

    private static func printToPDF(_ markdown: String, title: String, headerAndFooter: Bool = true) async throws -> PDFDocument {
        let info = PreviewPrinter.printInfo()
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = headerAndFooter
        let printer = PreviewPrinter(pageWidth: info.imageablePageBounds.width)
        try await printer.load(html: PreviewHTML.render(markdown))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("skinny-print-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        let operation = printer.operation(printInfo: info, title: title)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        defer { window.close() }
        let done = PrintDone()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            done.continuation = continuation
            operation.runModal(
                for: window,
                delegate: done,
                didRun: #selector(PrintDone.didRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
        let data = try Data(contentsOf: url)
        return try #require(PDFDocument(data: data))
    }

    @Test func printDoesNotWaitForeverOnImages() async throws {
        let printer = PreviewPrinter(pageWidth: 540)
        let start = Date()
        // A non-routable address never answers, so only the timeout ends the wait.
        try await printer.load(
            html: PreviewHTML.render("![never](http://10.255.255.1/never.png)"),
            imageTimeout: 0.5
        )
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func fileMenuHasPrintOnCommandP() throws {
        let fileMenu = try #require(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
        let print = try #require(fileMenu.items.first { $0.title == "Print…" })
        #expect(print.keyEquivalent == "p")
        #expect(print.keyEquivalentModifierMask == .command)
        #expect(fileMenu.items.contains { $0.title == "Page Setup…" })
    }
}

/// AppKit calls `didRun` on its print thread, so this must not be main-actor isolated.
private final class PrintDone: NSObject, @unchecked Sendable {
    var continuation: CheckedContinuation<Void, Never>?

    @objc func didRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        continuation?.resume()
        continuation = nil
    }
}
#endif

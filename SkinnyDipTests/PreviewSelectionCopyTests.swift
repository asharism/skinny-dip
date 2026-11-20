#if os(macOS)
import AppKit
import Testing
import WebKit
import MarkdownCore
@testable import SkinnyDip

/// ⌘C in the Preview with a selection copies that part of the Markdown Source
/// (whole top-level blocks), through the real `preview.html`.
@MainActor
struct PreviewSelectionCopyTests {
    private static let markdown = """
    # Title

    First paragraph.

    - one
    - two

    Last paragraph.
    """

    @Test func noSelectionCopiesTheWholeDocument() async throws {
        let webView = try await Self.loadedPreview()
        #expect(await webView.selectedSourceRange(in: Self.markdown) == nil)
    }

    @Test func partOfAParagraphCopiesThatParagraph() async throws {
        let webView = try await Self.loadedPreview()
        try await Self.select(webView, """
            const text = document.querySelectorAll("#content > p")[0].firstChild;
            range.setStart(text, 2); range.setEnd(text, 7);
            """)
        let range = try #require(await webView.selectedSourceRange(in: Self.markdown))
        #expect(String(Self.markdown[range]) == "First paragraph.")
    }

    @Test func aDragAcrossBlocksCopiesEachOfThem() async throws {
        let webView = try await Self.loadedPreview()
        try await Self.select(webView, """
            range.setStart(document.querySelector("#content > p").firstChild, 3);
            range.setEnd(document.querySelector("#content li").firstChild, 1);
            """)
        let range = try #require(await webView.selectedSourceRange(in: Self.markdown))
        #expect(String(Self.markdown[range]) == "First paragraph.\n\n- one\n- two")
    }

    /// A triple-click ends at offset 0 of the next block; that block isn't copied.
    @Test func aTripleClickDoesNotSpillIntoTheNextBlock() async throws {
        let webView = try await Self.loadedPreview()
        try await Self.select(webView, """
            const p = document.querySelector("#content > p");
            range.setStart(p.firstChild, 0);
            range.setEnd(document.querySelector("#content ul"), 0);
            """)
        let range = try #require(await webView.selectedSourceRange(in: Self.markdown))
        #expect(String(Self.markdown[range]) == "First paragraph.")
    }

    /// ADR-0011: ⌘C in the Preview writes the touched blocks' Markdown as plain text only.
    @Test func plainCopyWritesTheSelectedBlocksAsPlainText() async throws {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.preview.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let webView = try await Self.loadedPreview()
        webView.pasteboard = pasteboard
        webView.markdown = Self.markdown
        try await Self.select(webView, """
            const items = document.querySelectorAll("#content li");
            range.setStart(items[0].firstChild, 1);
            range.setEnd(items[1].firstChild, 2);
            """)
        await webView.copySelection(.plain).value
        #expect(pasteboard.onlyFlavors == [.string])
        #expect(pasteboard.string(forType: .string) == "- one\n- two")
    }

    @Test func plainCopyWithNoSelectionDoesNothing() async throws {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.preview.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let webView = try await Self.loadedPreview()
        webView.pasteboard = pasteboard
        webView.markdown = Self.markdown
        MacClipboard(pasteboard: pasteboard).write(plainText: "before")
        await webView.copySelection(.plain).value
        #expect(pasteboard.string(forType: .string) == "before")
    }

    /// ⌘⇧C in the Preview is Copy as Rich Text: the whole document with no selection.
    @Test func richTextCopyWithNoSelectionCopiesTheWholeDocument() async throws {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.preview.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let webView = try await Self.loadedPreview()
        webView.pasteboard = pasteboard
        webView.markdown = Self.markdown
        await webView.copySelection(.richText).value
        #expect(pasteboard.string(forType: .string) == Self.markdown)
        #expect(pasteboard.data(forType: .html) != nil)
    }

    /// Edit › Copy follows the Preview's selection while it has focus, and the
    /// Editor's again once it loses focus.
    @Test func reportsItsSelectionWhileFocused() async throws {
        let coordinator = PreviewView.Coordinator()
        let webView = try await Self.loadedPreview(coordinator: coordinator)
        var states: [Bool?] = []
        webView.onCopyStateChange = { states.append($0) }
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)

        #expect(window.makeFirstResponder(webView))
        #expect(states.last == .some(false))

        try await Self.select(webView, """
            const p = document.querySelector("#content > p").firstChild;
            range.setStart(p, 0); range.setEnd(p, 5);
            """)
        for _ in 0..<40 where states.last != .some(true) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(states.last == .some(true))

        #expect(window.makeFirstResponder(nil))
        #expect(states.last == .some(nil))
    }

    /// Acceptance 5: in the focused Preview, ⌘C copies the list's Markdown as plain
    /// text and ⌘⇧C as rich text. Unfocused, it leaves ⌘C to the Edit menu.
    @Test func keyEquivalentsCopyOnlyWhileFocused() async throws {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.preview.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let webView = try await Self.loadedPreview()
        webView.pasteboard = pasteboard
        webView.markdown = Self.markdown
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        func key(_ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: 8
            ))
        }

        window.makeFirstResponder(nil)
        MacClipboard(pasteboard: pasteboard).write(plainText: "before")
        #expect(!webView.performKeyEquivalent(with: try key("c", .command)))

        // Focusing the page clears its selection, so select after focusing.
        #expect(window.makeFirstResponder(webView))
        try await Self.select(webView, """
            const items = document.querySelectorAll("#content li");
            range.setStart(items[0].firstChild, 1);
            range.setEnd(items[1].firstChild, 2);
            """)
        #expect(webView.performKeyEquivalent(with: try key("c", .command)))
        for _ in 0..<40 where pasteboard.string(forType: .string) == "before" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(pasteboard.onlyFlavors == [.string])
        #expect(pasteboard.string(forType: .string) == "- one\n- two")

        #expect(webView.performKeyEquivalent(with: try key("C", [.command, .shift])))
        for _ in 0..<40 where pasteboard.data(forType: .html) == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(pasteboard.string(forType: .string) == "- one\n- two")
        #expect(pasteboard.data(forType: .html).map { String(decoding: $0, as: UTF8.self).contains("<li>") } == true)
    }

    /// ⌘? (⇧⌘/) opens the Help menu's search. AppKit offers key equivalents to
    /// every view before the menu bar, so the Preview must not claim it, focused or not.
    @Test func previewLeavesTheHelpShortcutToTheMenu() async throws {
        let webView = try await Self.loadedPreview()
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "?", charactersIgnoringModifiers: "?",
            isARepeat: false, keyCode: 44
        ))
        window.makeFirstResponder(nil)
        #expect(!webView.performKeyEquivalent(with: event))
        #expect(window.makeFirstResponder(webView))
        #expect(!webView.performKeyEquivalent(with: event))
    }

    private static func select(_ webView: WKWebView, _ body: String) async throws {
        _ = try await webView.callAsyncJavaScript(
            "const range = document.createRange();\n\(body)\nconst s = getSelection(); s.removeAllRanges(); s.addRange(range);",
            contentWorld: .page
        )
    }

    private static func loadedPreview(coordinator: PreviewView.Coordinator? = nil) async throws -> PreviewWebView {
        let configuration = WKWebViewConfiguration()
        if let coordinator {
            configuration.userContentController.add(coordinator, name: "previewSelection")
        }
        let webView = PreviewWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        coordinator?.webView = webView
        let page = try #require(WebBundleResources.page(named: "preview.html"))
        webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript("typeof selectedSourceLines")) as? String == "function" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        _ = try await webView.callAsyncJavaScript(
            "setScrollSync(false); render(html);",
            arguments: ["html": PreviewHTML.render(markdown)],
            contentWorld: .page
        )
        return webView
    }
}
#endif

#if os(macOS)
import AppKit
import Testing
import WebKit
@testable import SkinnyDip

/// Issue #6: verify native text wiring in the bundled CodeMirror editor (WKWebView + JS).
@MainActor
struct EditorNativeTextTests {
    @Test func bundledEditorEnablesNativeTextAttributes() async throws {
        let harness = try await EditorTestHarness.load()
        defer { harness.teardown() }

        let attrs = try await harness.evaluateContentAttributes()
        #expect(attrs.spellcheck == "true")
        #expect(attrs.autocorrect == "on")
        #expect(attrs.writingsuggestions == "true")
    }

    @Test func writingToolsSelectionExpandsToFullLines() async throws {
        let harness = try await EditorTestHarness.load()
        defer { harness.teardown() }

        try await harness.setDocument("alpha\nbeta gamma\n")
        try await harness.setSelection(from: 7, to: 11)
        try await harness.ensureWritingToolsSelection()

        let range = try await harness.mainSelection()
        let text = try await harness.documentText()
        let line = text.split(separator: "\n", omittingEmptySubsequences: false)[1]
        let lineStart = text.distance(from: text.startIndex, to: line.startIndex)
        let lineEnd = text.distance(from: text.startIndex, to: line.endIndex)
        #expect(range.from == lineStart)
        #expect(range.to == lineEnd)
    }

    @Test func webKitSpellCheckingDefaultsAreOn() {
        EditorTextCheckerDefaults.enable()
        for key in EditorTextCheckerDefaults.keys {
            #expect(UserDefaults.standard.bool(forKey: key))
        }
    }

    @Test func controlAThroughAppKitMovesToLineStart() async throws {
        let harness = try await AppKitEditorHarness.load()
        defer { harness.teardown() }

        try await harness.setDocument("hello world")
        try await harness.setSelection(from: 11, to: 11)
        harness.performControlKey(characters: "a", keyCode: 0)
        try await Task.sleep(nanoseconds: 300_000_000)
        let head = try await harness.mainSelection().to
        #expect(head == 0)
    }

    @Test func controlShiftDownThroughAppKitAddsCursor() async throws {
        let harness = try await AppKitEditorHarness.load()
        defer { harness.teardown() }

        try await harness.setDocument("one\ntwo\n")
        try await harness.setSelection(from: 1, to: 1)
        harness.performControlKey(characters: "\u{F701}", keyCode: 125, shift: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        let rangeCount = try await harness.selectionRangeCount()
        #expect(rangeCount >= 2)
    }

    @Test func controlShiftDownAddsSecondCursor() async throws {
        let harness = try await EditorTestHarness.load()
        defer { harness.teardown() }

        try await harness.setDocument("one\ntwo\n")
        try await harness.setSelection(from: 1, to: 1)
        try await harness.simulateKey(key: "ArrowDown", control: true, shift: true)
        let rangeCount = try await harness.selectionRangeCount()
        #expect(rangeCount >= 2)
    }

    @Test func editorWebViewExposesNativeAccessibilityAndWritingTools() {
        let configuration = WKWebViewConfiguration()
        configuration.writingToolsBehavior = .complete
        let webView = EditorWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        #expect(webView.accessibilityRole() == .textArea)
        #expect(webView.responds(to: AppWritingTools.webKitAction))
    }

    @Test func bundledScriptContainsNativeTextHooks() throws {
        let url =
            Bundle.main.url(forResource: "editor", withExtension: "bundle.js", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "editor", withExtension: "bundle.js")
        guard let url else {
            Issue.record("editor.bundle.js missing from app bundle")
            return
        }
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("ensureWritingToolsSelection"))
        #expect(source.contains("focusEditor"))
    }
}

@MainActor
private final class EditorTestHarness: NSObject, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var ready = false

    static func load() async throws -> EditorTestHarness {
        let configuration = WKWebViewConfiguration()
        configuration.writingToolsBehavior = .complete
        let harness = EditorTestHarness()
        configuration.userContentController.add(harness, name: "editor")
        harness.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), configuration: configuration)

        guard let page = WebBundleResources.page(named: "editor.html"),
              let readAccess = WebBundleResources.readAccessRoot()
        else {
            throw HarnessError.missingResources
        }

        harness.webView.loadFileURL(page, allowingReadAccessTo: readAccess)
        try await harness.waitUntilReady(timeout: 15)
        return harness
    }

    private override init() {
        super.init()
    }

    func teardown() {
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "editor")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              body["event"] as? String == "editorReady"
        else { return }
        ready = true
    }

    func evaluateContentAttributes() async throws -> (spellcheck: String?, autocorrect: String?, writingsuggestions: String?) {
        let value = try await webView.callAsyncJavaScript(
            """
            const el = document.querySelector('.cm-content');
            return {
              spellcheck: el?.getAttribute('spellcheck'),
              autocorrect: el?.getAttribute('autocorrect'),
              writingsuggestions: el?.getAttribute('writingsuggestions'),
            };
            """,
            contentWorld: .page
        )
        let dict = value as? [String: String]
        return (
            dict?["spellcheck"],
            dict?["autocorrect"],
            dict?["writingsuggestions"]
        )
    }

    func setDocument(_ text: String) async throws {
        _ = try await webView.callAsyncJavaScript(
            "return setDocument(text)",
            arguments: ["text": text],
            contentWorld: .page
        )
    }

    func documentText() async throws -> String {
        let value = try await webView.callAsyncJavaScript(
            "return window.editorView.state.doc.toString()",
            contentWorld: .page
        )
        return value as? String ?? ""
    }

    func setSelection(from: Int, to: Int) async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            const view = window.editorView;
            view.dispatch({ selection: { anchor: from, head: to } });
            view.focus();
            return true;
            """,
            arguments: ["from": from, "to": to],
            contentWorld: .page
        )
    }

    func mainSelection() async throws -> (from: Int, to: Int) {
        let value = try await webView.callAsyncJavaScript(
            """
            const main = window.editorView.state.selection.main;
            return { from: main.from, to: main.to };
            """,
            contentWorld: .page
        )
        let dict = value as? [String: Int]
        return (dict?["from"] ?? 0, dict?["to"] ?? 0)
    }

    func selectionRangeCount() async throws -> Int {
        let value = try await webView.callAsyncJavaScript(
            "return window.editorView.state.selection.ranges.length",
            contentWorld: .page
        )
        return value as? Int ?? 0
    }

    func ensureWritingToolsSelection() async throws {
        _ = try await webView.callAsyncJavaScript(
            "return ensureWritingToolsSelection()",
            contentWorld: .page
        )
    }

    func simulateKey(key: String, control: Bool = false, shift: Bool = false) async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            const view = window.editorView;
            const target = view.contentDOM;
            const init = {
              key: key,
              code: key,
              ctrlKey: control,
              shiftKey: shift,
              bubbles: true,
              cancelable: true,
            };
            target.dispatchEvent(new KeyboardEvent('keydown', init));
            target.dispatchEvent(new KeyboardEvent('keyup', init));
            return view.state.selection.main.head;
            """,
            arguments: ["key": key, "control": control, "shift": shift],
            contentWorld: .page
        )
    }

    private func waitUntilReady(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !ready {
            try await Task.sleep(nanoseconds: 50_000_000)
            if Date() > deadline { throw HarnessError.timeout }
        }
        _ = try? await webView.callAsyncJavaScript("return focusEditor()", contentWorld: .page)
    }

    private enum HarnessError: Error {
        case missingResources
        case timeout
        case noKeyEvent
    }
}
#endif

@MainActor
private final class AppKitEditorHarness: NSObject, WKScriptMessageHandler {
    private var webView: EditorWebView!
    private var window: NSWindow!
    private var ready = false

    static func load() async throws -> AppKitEditorHarness {
        EditorTextCheckerDefaults.enable()
        let configuration = WKWebViewConfiguration()
        configuration.writingToolsBehavior = .complete
        let harness = AppKitEditorHarness()
        configuration.userContentController.add(harness, name: "editor")
        harness.webView = EditorWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 400),
            configuration: configuration
        )
        harness.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        harness.window.contentView = harness.webView
        harness.window.makeKeyAndOrderFront(nil)

        guard let page = WebBundleResources.page(named: "editor.html"),
              let readAccess = WebBundleResources.readAccessRoot()
        else {
            throw EditorTestHarnessError.missingResources
        }
        harness.webView.loadFileURL(page, allowingReadAccessTo: readAccess)
        try await harness.waitUntilReady(timeout: 15)
        harness.window.makeFirstResponder(harness.webView)
        return harness
    }

    func teardown() {
        webView.stopLoading()
        window.close()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              body["event"] as? String == "editorReady"
        else { return }
        ready = true
    }

    func setDocument(_ text: String) async throws {
        _ = try await webView.callAsyncJavaScript(
            "return setDocument(text)",
            arguments: ["text": text],
            contentWorld: .page
        )
    }

    func setSelection(from: Int, to: Int) async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            const view = window.editorView;
            view.dispatch({ selection: { anchor: from, head: to } });
            view.focus();
            return true;
            """,
            arguments: ["from": from, "to": to],
            contentWorld: .page
        )
    }

    func mainSelection() async throws -> (from: Int, to: Int) {
        let value = try await webView.callAsyncJavaScript(
            """
            const main = window.editorView.state.selection.main;
            return { from: main.from, to: main.to };
            """,
            contentWorld: .page
        )
        let dict = value as? [String: Int]
        return (dict?["from"] ?? 0, dict?["to"] ?? 0)
    }

    func selectionRangeCount() async throws -> Int {
        let value = try await webView.callAsyncJavaScript(
            "return window.editorView.state.selection.ranges.length",
            contentWorld: .page
        )
        return value as? Int ?? 0
    }

    func performControlKey(characters: String, keyCode: UInt16, shift: Bool = false) {
        var flags: NSEvent.ModifierFlags = .control
        if shift { flags.insert(.shift) }
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else { return }
        _ = webView.performKeyEquivalent(with: event)
    }

    private func waitUntilReady(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !ready {
            try await Task.sleep(nanoseconds: 50_000_000)
            if Date() > deadline { throw EditorTestHarnessError.timeout }
        }
        _ = try? await webView.callAsyncJavaScript("return focusEditor()", contentWorld: .page)
    }
}

private enum EditorTestHarnessError: Error {
    case missingResources
    case timeout
}

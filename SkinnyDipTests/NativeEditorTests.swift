#if os(macOS)
import AppKit
import MarkdownCore
import SwiftUI
import Testing
@testable import SkinnyDip

/// The native Editor Backend (ADR-0010, #64), hosted in a real window like the
/// `EditorNativeTextTests` harness, with SwiftUI bindings into a plain model.
@MainActor
struct NativeEditorTests {
    @Test func textRoundTrip() async throws {
        let harness = NativeEditorHarness(text: "Hello")
        defer { harness.teardown() }
        #expect(harness.textView.string == "Hello")

        // Typing reaches the binding after the debounce, without echoing back.
        harness.textView.setSelectedRange(NSRange(location: 5, length: 0))
        harness.event { harness.textView.insertText(" world", replacementRange: harness.textView.selectedRange()) }
        #expect(harness.model.text == "Hello")
        try await harness.waitForBinding { $0.text == "Hello world" }
        harness.event { harness.update() }
        #expect(harness.textView.string == "Hello world")

        // An outside change (restore, a reload) replaces the text as one undoable edit.
        harness.model.text = "Replaced"
        harness.event { harness.update() }
        #expect(harness.textView.string == "Replaced")
        harness.textView.undoManager?.undo()
        #expect(harness.textView.string == "Hello world")
    }

    @Test func selectionUTF16AroundEmoji() {
        let harness = NativeEditorHarness(text: "a👋🏽b\r\nc")
        defer { harness.teardown() }

        harness.textView.setSelectedRange(NSRange(location: 1, length: 4))
        #expect(harness.model.selection.map { String(harness.model.text[$0]) } == "👋🏽")
        #expect(harness.model.hasEditorSelection)
        #expect(harness.controller.cursorUTF16 == 1)

        harness.textView.setSelectedRange(NSRange(location: 8, length: 1))
        #expect(harness.model.selection.map { String(harness.model.text[$0]) } == "c")
        #expect(harness.controller.cursorUTF16 == 8)

        harness.textView.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(harness.model.selection == nil)
        #expect(!harness.model.hasEditorSelection)
    }

    @Test func pasteAsMarkdownIsOneUndoStep() async throws {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.native.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let harness = NativeEditorHarness(text: "")
        defer { harness.teardown() }
        harness.textView.pasteboard = pasteboard

        harness.event { harness.textView.insertText("Intro\n", replacementRange: NSRange(location: 0, length: 0)) }
        let item = NSPasteboardItem()
        item.setString("<h1>Title</h1><ul><li><b>Bold</b> item</li></ul>", forType: .html)
        item.setString("Title\nBold item", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        harness.event { harness.textView.insertMarkdownFromPasteboard(plain: false) }
        #expect(harness.textView.string == "Intro\n# Title\n\n- **Bold** item")
        try await harness.waitForBinding { $0.canUndo }
        harness.textView.skinnyDipUndo(nil)
        #expect(harness.textView.string == "Intro\n")

        harness.event { harness.textView.insertMarkdownFromPasteboard(plain: true) }
        #expect(harness.textView.string == "Intro\nTitle\nBold item")
    }

    @Test func highlightingAddsNoUndoAndNoEdit() async throws {
        let harness = NativeEditorHarness(text: "# Heading\n\nSome *soft* text\n")
        defer { harness.teardown() }
        let storage = try #require(harness.textView.textStorage)

        harness.coordinator.highlightNow()
        let heading = storage.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor
        #expect(heading == NativeEditorTheme(vars: harness.themeVars).color(for: .heading))
        #expect(harness.textView.undoManager?.canUndo == false)
        #expect(!harness.model.canUndo)
        #expect(harness.model.textWrites == 0)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(harness.model.textWrites == 0)
    }

    @Test func copySourceUsesSelection() {
        let harness = NativeEditorHarness(text: "one **two** three")
        defer { harness.teardown() }
        harness.textView.setSelectedRange(NSRange(location: 4, length: 7))
        let source = harness.textView.copySource()
        #expect(source.markdown == "one **two** three")
        #expect(source.selection.map { String(source.markdown[$0]) } == "**two**")

        harness.textView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(harness.textView.copySource().selection == nil)
    }

    @Test func viewportReportsTopLineAfterScroll() async throws {
        let text = (1...300).map { "Line \($0)" }.joined(separator: "\n")
        let harness = NativeEditorHarness(text: text)
        defer { harness.teardown() }

        harness.coordinator.scrollToLine(120)
        try await harness.waitForController { $0.viewport.topLine == 120 }
        #expect(harness.controller.viewport.topLine == 120)
        #expect(harness.controller.viewport.fraction < 0.5)
    }

    @Test func tabCloseReleasesTextView() async throws {
        weak var textView: NativeEditorTextView?
        weak var coordinator: NativeEditorView.Coordinator?
        autoreleasepool {
            let harness = NativeEditorHarness(text: "# Title\n\nBody *text*\n")
            textView = harness.textView
            coordinator = harness.coordinator
            harness.event { harness.textView.insertText("x", replacementRange: NSRange(location: 0, length: 0)) }
            harness.coordinator.highlightNow()
            harness.teardown()
        }
        // AppKit's own delayed work (spell checking) lets go of the view a moment later.
        let deadline = Date().addingTimeInterval(3)
        while textView != nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(textView == nil)
        #expect(coordinator == nil)
    }

    @Test func smartQuotesOff() {
        let harness = NativeEditorHarness(text: "")
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView
        #expect(!textView.isAutomaticQuoteSubstitutionEnabled)
        #expect(!textView.isAutomaticDashSubstitutionEnabled)
        #expect(!textView.isAutomaticTextReplacementEnabled)
        #expect(textView.isContinuousSpellCheckingEnabled)
        #expect(textView.isAutomaticSpellingCorrectionEnabled == NSSpellChecker.isAutomaticSpellingCorrectionEnabled)
        #expect(!textView.isRichText)
        #expect(textView.writingToolsBehavior == .complete)
        #expect(textView.textLayoutManager != nil)
    }
}

@MainActor
final class NativeEditorModel {
    var text: String { didSet { textWrites += 1 } }
    var selection: Range<String.Index>?
    var canUndo = false
    var canRedo = false
    var hasEditorSelection = false
    var textWrites = 0

    init(text: String) {
        self.text = text
        textWrites = 0
    }
}

/// A native editor in an offscreen window, built the way `makeNSView` builds it.
@MainActor
final class NativeEditorHarness {
    let model: NativeEditorModel
    let controller = EditorController()
    let themeVars: [String: String]
    private(set) var coordinator: NativeEditorView.Coordinator!
    private(set) var textView: NativeEditorTextView!
    private var window: NSWindow?

    init(text: String) {
        model = NativeEditorModel(text: text)
        var vars = ThemeStore().resolved(mode: ThemeSelection.matchSystem, fixed: ThemeSelection.defaultLight, light: ThemeSelection.defaultLight, dark: ThemeSelection.defaultDark, systemIsDark: false).cssVariables()
        vars["--editor-font-size"] = "13.0px"
        vars["--editor-inline-pad"] = "22.0px"
        vars["--zoom"] = "1.0"
        themeVars = vars
        let view = makeView()
        coordinator = view.makeCoordinator()
        let scrollView = coordinator.makeScrollView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        scrollView.frame = window.contentView!.bounds
        scrollView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(scrollView)
        self.window = window
        textView = coordinator.textView
        textView.undoManager?.groupsByEvent = false
        window.layoutIfNeeded()
        window.displayIfNeeded()
        coordinator.update(from: view)
    }

    func makeView() -> NativeEditorView {
        let model = model
        return NativeEditorView(
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            selection: Binding(get: { model.selection }, set: { model.selection = $0 }),
            canUndo: Binding(get: { model.canUndo }, set: { model.canUndo = $0 }),
            canRedo: Binding(get: { model.canRedo }, set: { model.canRedo = $0 }),
            hasEditorSelection: Binding(get: { model.hasEditorSelection }, set: { model.hasEditorSelection = $0 }),
            documentID: UUID(),
            themeVars: themeVars,
            controller: controller
        )
    }

    /// AppKit groups undo by event. Hosted tests get no events, so each
    /// simulated keystroke or menu command is its own group.
    func event(_ body: () -> Void) {
        let undoManager = textView.undoManager!
        undoManager.beginUndoGrouping()
        body()
        undoManager.endUndoGrouping()
    }

    /// What SwiftUI does after a binding changes.
    func update() {
        coordinator.update(from: makeView())
    }

    func waitForBinding(timeout: TimeInterval = 2, _ condition: (NativeEditorModel) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(model) && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func waitForController(timeout: TimeInterval = 2, _ condition: (EditorController) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(controller) && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func teardown() {
        coordinator?.tearDown()
        window?.makeFirstResponder(nil)
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        window?.close()
        window = nil
        coordinator = nil
        textView = nil
    }
}
#endif

#if os(macOS)
import AppKit
import MarkdownCore
import SwiftUI
import Testing
@testable import SkinnyDip

/// The native editor (ADR-0010, #64), hosted in a real window with SwiftUI
/// bindings into a plain model.
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

    /// Pasting Skinny's own Copy as Rich Text back in takes the Markdown flavor,
    /// so the source comes back exactly, not a lossy HTML round trip.
    @Test func pastingOurOwnCopyInsertsItsMarkdownSource() {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.native.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let harness = NativeEditorHarness(text: "")
        defer { harness.teardown() }
        harness.textView.pasteboard = pasteboard

        MacClipboard(pasteboard: pasteboard).write(CopyAsRichText.payload(for: "# Notes\n\n* starred_item\n"))
        harness.event { harness.textView.insertMarkdownFromPasteboard(plain: false) }
        #expect(harness.textView.string == "# Notes\n\n* starred_item\n")
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

    /// Bold and italic are display-only: they follow the parse, so a run that
    /// stops being `**strong**` goes back to Regular, and the text never changes.
    @Test func highlightingSetsBoldAndItalic() throws {
        let text = "# Head\n\n**bold** and *it* and ***bi*** x\n"
        let harness = NativeEditorHarness(text: text)
        defer { harness.teardown() }
        let storage = try #require(harness.textView.textStorage)
        func font(at index: Int) -> String? {
            (storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont)?.fontName
        }

        harness.coordinator.highlightNow()
        #expect(font(at: 2) == "CommitMono-Bold")         // H of the heading
        #expect(font(at: 10) == "CommitMono-Bold")        // b of **bold**
        #expect(font(at: 22) == "CommitMono-Italic")      // i of *it*
        #expect(font(at: 33) == "CommitMono-BoldItalic")  // b of ***bi***
        #expect(font(at: 39) == "CommitMono-Regular")     // plain x
        #expect(storage.string == text)

        // Break the strong run: its letters go back to Regular.
        storage.replaceCharacters(in: NSRange(location: 8, length: 2), with: "")
        harness.coordinator.highlightNow()
        #expect(font(at: 8) == "CommitMono-Regular")
    }

    /// Commit Mono reaches the editor only if `ATSApplicationFontsPath` still
    /// points at the bundled folder; otherwise it falls back to SF Mono silently.
    @Test func editorUsesBundledCommitMono() {
        let theme = NativeEditorTheme(vars: [:])
        #expect(theme.font.fontName == "CommitMono-Regular")
        #expect(theme.lineHeight == (theme.fontSize * 1.8).rounded())
    }

    /// Expanded line height should leave the same space above and below the
    /// font's ascent/descent, including the continuation rows of a paragraph.
    @Test(arguments: [13.0, 14.0, 20.0, 26.0])
    func textIsVerticallyCenteredInExpandedLines(fontSize: Double) throws {
        let harness = NativeEditorHarness(text: "Call out\n" + String(repeating: "exploration words ", count: 12))
        defer { harness.teardown() }
        // Exercise the same restyling path used by Zoom and font-size changes.
        harness.themeVars["--editor-font-size"] = "\(fontSize)px"
        harness.themeVars["--zoom"] = "\(fontSize / 13)"
        harness.update()
        let manager = try #require(harness.textView.textLayoutManager)
        manager.ensureLayout(for: manager.documentRange)
        let theme = NativeEditorTheme(vars: harness.themeVars)
        let font = theme.font
        var count = 0
        manager.enumerateTextLayoutFragments(from: manager.documentRange.location, options: [.ensuresLayout]) { fragment in
            for line in fragment.textLineFragments where line.characterRange.length > 0 {
                let offset = line.attributedString.attribute(.baselineOffset, at: line.characterRange.location, effectiveRange: nil) as? CGFloat ?? 0
                let fontCenter = line.typographicBounds.minY + line.glyphOrigin.y - offset - (font.ascender + font.descender) / 2
                #expect(abs(fontCenter - line.typographicBounds.midY) < 0.6,
                        "font center \(fontCenter), row center \(line.typographicBounds.midY), baseline \(line.glyphOrigin.y)")
                #expect(abs(line.typographicBounds.height - theme.lineHeight) < 0.6)
                count += 1
            }
            return true
        }
        #expect(count >= 3)
        #expect(harness.textView.undoManager?.canUndo == false)
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

    /// ADR-0011: ⌘C and ⌘X write the selected Markdown as plain text only.
    @Test func copyWritesPlainTextOnly() {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.native.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let harness = NativeEditorHarness(text: "one **two** three")
        defer { harness.teardown() }
        harness.textView.pasteboard = pasteboard

        harness.textView.setSelectedRange(NSRange(location: 4, length: 7))
        harness.textView.copy(nil)
        #expect(pasteboard.onlyFlavors == [.string])
        #expect(pasteboard.string(forType: .string) == "**two**")
        #expect(harness.textView.string == "one **two** three")
    }

    @Test func copyWithNoSelectionDoesNothingAndIsDisabled() {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.native.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let harness = NativeEditorHarness(text: "one **two** three")
        defer { harness.teardown() }
        harness.textView.pasteboard = pasteboard
        MacClipboard(pasteboard: pasteboard).write(plainText: "before")

        harness.textView.setSelectedRange(NSRange(location: 3, length: 0))
        harness.textView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "before")

        let copyItem = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        #expect(!harness.textView.validateUserInterfaceItem(copyItem))
        harness.textView.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(harness.textView.validateUserInterfaceItem(copyItem))
    }

    @Test func cutWritesPlainTextAndUndoesInOneStep() {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.native.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let text = "first\nsecond **line**\nthird"
        let harness = NativeEditorHarness(text: text)
        defer { harness.teardown() }
        harness.textView.pasteboard = pasteboard

        harness.textView.setSelectedRange((text as NSString).range(of: "second **line**\n"))
        harness.event { harness.textView.cut(nil) }
        #expect(harness.textView.string == "first\nthird")
        #expect(pasteboard.onlyFlavors == [.string])
        #expect(pasteboard.string(forType: .string) == "second **line**\n")

        // Pasting it back arrives unchanged; one undo removes the paste, one more restores the cut.
        harness.event { harness.textView.paste(nil) }
        #expect(harness.textView.string == text)
        harness.textView.undoManager?.undo()
        #expect(harness.textView.string == "first\nthird")
        harness.textView.undoManager?.undo()
        #expect(harness.textView.string == text)
    }

    /// The context menu's Copy is the plain Copy, followed by Copy as Rich Text and Copy as HTML.
    @Test func contextMenuOffersPlainCopyRichTextAndHTML() throws {
        let harness = NativeEditorHarness(text: "one **two** three")
        defer { harness.teardown() }
        harness.textView.setSelectedRange(NSRange(location: 4, length: 7))
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0,
            windowNumber: harness.textView.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let menu = try #require(harness.textView.menu(for: event))
        let titles = menu.items.map(\.title)
        let copyIndex = try #require(titles.firstIndex(of: "Copy"))
        #expect(Array(titles[copyIndex...].prefix(3)) == ["Copy", "Copy as Rich Text", "Copy as HTML"])
        #expect(!titles.contains("Copy as Markdown"))
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

    // MARK: Line numbers (#76)

    @Test func lineNumberGutterKeepsTextKit2() async throws {
        var fellBack: [ObjectIdentifier] = []
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextView.willSwitchToNSLayoutManagerNotification, object: nil, queue: nil
        ) { note in
            if let object = note.object as AnyObject? { fellBack.append(ObjectIdentifier(object)) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let text = (1...150).map { "Line \($0) " + String(repeating: "wrap ", count: $0 % 7 == 0 ? 40 : 1) }.joined(separator: "\n")
        let harness = NativeEditorHarness(text: text)
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView

        // Draw, type, scroll, zoom and toggle: every path the gutter takes.
        harness.display()
        harness.event { textView.insertText("\nnew", replacementRange: NSRange(location: 0, length: 0)) }
        harness.display()
        harness.coordinator.scrollToLine(120)
        harness.display()
        harness.themeVars["--editor-font-size"] = "16.0px"
        harness.themeVars["--zoom"] = "1.2"
        harness.update()
        harness.display()
        harness.model.showsLineNumbers = false
        harness.update()
        harness.display()
        harness.model.showsLineNumbers = true
        harness.update()
        harness.display()
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(textView.textLayoutManager != nil)
        #expect(!fellBack.contains(ObjectIdentifier(textView)))
        #expect(fellBack.isEmpty)
    }

    @Test func gutterWidthGrowsAtHundredLines() {
        let ninetyNine = (1...99).map { "\($0)" }.joined(separator: "\n")
        let harness = NativeEditorHarness(text: ninetyNine)
        defer { harness.teardown() }
        let narrow = harness.coordinator.gutterWidth
        let narrowOrigin = harness.textView.textContainerOrigin.x
        #expect(narrow > 0)

        harness.event { harness.textView.insertText("\n100", replacementRange: NSRange(location: (ninetyNine as NSString).length, length: 0)) }
        #expect(harness.coordinator.gutterWidth > narrow)
        #expect(harness.textView.textContainerOrigin.x > narrowOrigin)

        // Back under 100 lines, it narrows again.
        harness.event { harness.textView.insertText("", replacementRange: NSRange(location: (ninetyNine as NSString).length, length: 4)) }
        #expect(harness.textView.string == ninetyNine)
        #expect(harness.coordinator.gutterWidth == narrow)
    }

    @Test func gutterNumbersLogicalLinesOnly() {
        let long = String(repeating: "wrapping words ", count: 40)
        let harness = NativeEditorHarness(text: "short\n\(long)\nend\n")
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView
        let rows = harness.coordinator.gutterRows(in: textView.bounds, textView: textView)
        // The wrapped paragraph gets one number, and the empty last line is numbered.
        #expect(rows.map(\.line) == [1, 2, 3, 4])
        let lineHeight = NativeEditorTheme(vars: harness.themeVars).lineHeight
        #expect(rows.allSatisfy { abs($0.rect.height - lineHeight) < 1 })
        #expect(rows[2].rect.minY - rows[1].rect.minY > lineHeight * 3)
        #expect(rows[3].rect.minY > rows[2].rect.minY)

        let empty = NativeEditorHarness(text: "")
        defer { empty.teardown() }
        #expect(empty.coordinator.gutterRows(in: empty.textView.bounds, textView: empty.textView).map(\.line) == [1])
    }

    @Test func gutterMatchesLinesFarDown() async throws {
        let text = (1...2000).map { "Line \($0)" }.joined(separator: "\n")
        let harness = NativeEditorHarness(text: text)
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView
        harness.coordinator.scrollToLine(1500)
        let rows = harness.coordinator.gutterRows(in: textView.visibleRect, textView: textView)
        let first = try #require(rows.first { $0.rect.minY >= textView.visibleRect.minY - 1 })
        #expect(first.line == 1500)
        // One number per row, consecutive, with no gaps or repeats.
        let numbers = rows.map(\.line)
        #expect(numbers == Array(numbers[0]..<(numbers[0] + numbers.count)))
        // Scroll sync still reports the same top line, with the gutter on and off.
        try await harness.waitForController { $0.viewport.topLine == 1500 }
        #expect(harness.controller.viewport.topLine == 1500)
        harness.model.showsLineNumbers = false
        harness.update()
        harness.coordinator.scrollToLine(1200)
        try await harness.waitForController { $0.viewport.topLine == 1200 }
        #expect(harness.controller.viewport.topLine == 1200)
    }

    @Test func toggleHidesGutter() {
        let harness = NativeEditorHarness(text: "one\ntwo\nthree")
        defer { harness.teardown() }
        let theme = NativeEditorTheme(vars: harness.themeVars)
        #expect(harness.coordinator.gutterWidth > 0)
        #expect(harness.textView.textContainerOrigin.x > theme.inlinePadding)
        // A separate column (strip tint, border2 hairline), then the gap, then the text.
        let gutter = harness.coordinator.gutter
        #expect(gutter.columnWidth > 0)
        #expect(abs(harness.textView.textContainerOrigin.x - gutter.columnWidth - 8) < 0.01, "\(harness.textView.textContainerOrigin.x) \(gutter.columnWidth)")
        #expect(gutter.numberRight < gutter.columnWidth - NativeEditorGutter.hairline)
        #expect(theme.gutterBackground == NativeEditorTheme.color(css: harness.themeVars["--gutter-bg"] ?? ""))
        #expect(theme.gutterBorder == NativeEditorTheme.color(css: harness.themeVars["--gutter-border"] ?? ""))

        harness.model.showsLineNumbers = false
        harness.update()
        #expect(harness.coordinator.gutterWidth == 0)
        #expect(harness.textView.textContainerOrigin == NSPoint(x: theme.inlinePadding, y: theme.insets.top))

        harness.model.showsLineNumbers = true
        harness.update()
        #expect(harness.coordinator.gutterWidth > 0)
    }
}

// MARK: Current-line highlight (#77)

@MainActor
struct NativeEditorCurrentLineTests {
    @Test func currentLineRectCoversWrappedParagraph() throws {
        let long = String(repeating: "wrapping words ", count: 40)
        let harness = NativeEditorHarness(text: "short\n\(long)\nend")
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView
        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        let paragraphStart = 6
        let location = try #require(contentManager.location(layoutManager.documentRange.location, offsetBy: paragraphStart))
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let fragment = try #require(layoutManager.textLayoutFragment(for: location))
        #expect(fragment.textLineFragments.count >= 3)
        let third = fragment.textLineFragments[2]

        textView.setSelectedRange(NSRange(location: paragraphStart + third.characterRange.location + 2, length: 0))
        let rect = try #require(harness.coordinator.currentLineRect())
        #expect(abs(rect.height - fragment.layoutFragmentFrame.height) < 0.5)
        #expect(abs(rect.minY - (fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y)) < 0.5)
        // One band from the left edge to the right edge of the text view.
        #expect(rect.minX == 0)
        #expect(rect.width == textView.bounds.width)

        // A one-row line, and the last line.
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        let short = try #require(harness.coordinator.currentLineRect())
        #expect(short.height < rect.height / 2)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        #expect(harness.coordinator.currentLineRect()?.minY ?? 0 > rect.maxY - 1)
    }

    @Test func currentLineOnEmptyLastLine() throws {
        let harness = NativeEditorHarness(text: "a\nb\n")
        defer { harness.teardown() }
        harness.textView.setSelectedRange(NSRange(location: 2, length: 0))
        let second = try #require(harness.coordinator.currentLineRect())
        harness.textView.setSelectedRange(NSRange(location: 4, length: 0))
        let last = try #require(harness.coordinator.currentLineRect())
        #expect(abs(last.minY - second.maxY) < 1)
        #expect(abs(last.height - second.height) < 1)

        let empty = NativeEditorHarness(text: "")
        defer { empty.teardown() }
        let rect = try #require(empty.coordinator.currentLineRect())
        #expect(abs(rect.height - second.height) < 1)
    }

    @Test func noHighlightWithSelection() {
        let harness = NativeEditorHarness(text: "one\ntwo\nthree")
        defer { harness.teardown() }
        harness.textView.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(harness.coordinator.currentLineRect() != nil)
        harness.textView.setSelectedRange(NSRange(location: 4, length: 2))
        #expect(harness.coordinator.currentLineRect() == nil)
        harness.textView.setSelectedRange(NSRange(location: 5, length: 0))
        #expect(harness.coordinator.currentLineRect() != nil)
    }

    @Test func highlightDoesNotEditOrUndo() async throws {
        let harness = NativeEditorHarness(text: "# Title\n\nBody text\nMore")
        defer { harness.teardown() }
        let storage = try #require(harness.textView.textStorage)
        let before = NSAttributedString(attributedString: storage)
        for offset in [0, 3, 9, 14, 20, 2] {
            harness.textView.setSelectedRange(NSRange(location: offset, length: 0))
            harness.display()
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(harness.textView.undoManager?.canUndo == false)
        #expect(!harness.model.canUndo)
        #expect(harness.model.textWrites == 0)
        // No background attributes: the band is drawn, never stored in the text.
        #expect(storage.isEqual(to: before))
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            #expect(value == nil)
        }
    }
}

@MainActor
final class NativeEditorModel {
    var text: String { didSet { textWrites += 1 } }
    var selection: Range<String.Index>?
    var canUndo = false
    var canRedo = false
    var hasEditorSelection = false
    var showsLineNumbers = true
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
    var themeVars: [String: String]
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
            controller: controller,
            showsLineNumbers: model.showsLineNumbers
        )
    }

    /// Draws the window now, so the gutter's drawing code runs.
    func display() {
        window?.layoutIfNeeded()
        window?.contentView?.needsDisplay = true
        window?.displayIfNeeded()
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

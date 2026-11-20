#if os(macOS)
import AppKit
import Testing
@testable import SkinnyDip

/// Smart ⌘← (#95), driven by real key events through the window so the key
/// binding itself (`moveToLeftEndOfLine:`) is proven, not just the method.
@MainActor
struct NativeEditorLineStartTests {
    @Test func commandLeftGoesToContentThenColumnZero() throws {
        let harness = NativeEditorHarness(text: "intro\n- [ ] some task")
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))

        try commandLeft(textView)
        #expect(textView.selectedRange() == NSRange(location: 12, length: 0))
        try commandLeft(textView)
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
        try commandLeft(textView)
        #expect(textView.selectedRange() == NSRange(location: 12, length: 0))

        // ⌘⇧← from the end selects just the text, then the whole line.
        textView.setSelectedRange(NSRange(location: end, length: 0))
        try commandLeft(textView, shift: true)
        #expect(textView.selectedRange() == NSRange(location: 12, length: end - 12))
        #expect((textView.string as NSString).substring(with: textView.selectedRange()) == "some task")
        try commandLeft(textView, shift: true)
        #expect(textView.selectedRange() == NSRange(location: 6, length: end - 6))

        // A caret move, not an edit.
        #expect(textView.string == "intro\n- [ ] some task")
        #expect(textView.undoManager?.canUndo == false)

        // A plain line goes straight to column 0, like AppKit.
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        try commandLeft(textView)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test func commandLeftOnAWrappedRowUsesTheVisualRow() throws {
        let item = "- " + String(repeating: "wrapping words ", count: 30)
        let harness = NativeEditorHarness(text: "intro\n\(item)")
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView
        let window = try #require(textView.window)
        window.setContentSize(NSSize(width: 260, height: 300))
        window.layoutIfNeeded()

        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let paragraph = 6
        let location = try #require(contentManager.location(layoutManager.documentRange.location, offsetBy: paragraph))
        let rows = try #require(layoutManager.textLayoutFragment(for: location)?.textLineFragments)
        #expect(rows.count >= 3)
        let second = paragraph + rows[1].characterRange.location
        let third = paragraph + rows[2].characterRange.location

        // A continuation row: AppKit's start of that visual row.
        textView.setSelectedRange(NSRange(location: third + 4, length: 0))
        #expect(textView.isOnWrappedContinuationRow(third + 4))
        try commandLeft(textView)
        #expect(textView.selectedRange() == NSRange(location: third, length: 0))
        // Extending on a continuation row: AppKit's too.
        textView.setSelectedRange(NSRange(location: second + 4, length: 0))
        try commandLeft(textView, shift: true)
        #expect(textView.selectedRange() == NSRange(location: second, length: 4))

        // The first row is smart: the content start, then column 0.
        textView.setSelectedRange(NSRange(location: paragraph + 7, length: 0))
        #expect(!textView.isOnWrappedContinuationRow(paragraph + 7))
        try commandLeft(textView)
        #expect(textView.selectedRange() == NSRange(location: paragraph + 2, length: 0))
        try commandLeft(textView)
        #expect(textView.selectedRange() == NSRange(location: paragraph, length: 0))
    }

    @Test func controlAStaysAtColumnZero() throws {
        let harness = NativeEditorHarness(text: "- item")
        defer { harness.teardown() }
        let textView: NativeEditorTextView = harness.textView
        textView.setSelectedRange(NSRange(location: 6, length: 0))
        try sendKey(textView, characters: "\u{01}", ignoringModifiers: "a", flags: .control, keyCode: 0)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    // MARK: Key events

    /// ⌘← (or ⌘⇧←) as the keyboard sends it: the left-arrow function key.
    private func commandLeft(_ textView: NSTextView, shift: Bool = false) throws {
        let arrow = String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!)
        var flags: NSEvent.ModifierFlags = [.command, .function, .numericPad]
        if shift { flags.insert(.shift) }
        try sendKey(textView, characters: arrow, ignoringModifiers: arrow, flags: flags, keyCode: 123)
    }

    private func sendKey(_ textView: NSTextView, characters: String, ignoringModifiers: String, flags: NSEvent.ModifierFlags, keyCode: UInt16) throws {
        let window = try #require(textView.window)
        window.makeFirstResponder(textView)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: ignoringModifiers,
            isARepeat: false, keyCode: keyCode
        ))
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }
}
#endif

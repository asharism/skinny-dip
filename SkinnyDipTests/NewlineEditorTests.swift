#if os(macOS)
import AppKit
import MarkdownCore
import Testing
@testable import SkinnyDip

/// Enter continues lists and blockquotes (#90), driven through the window with
/// real Return key events so the key binding itself is proven.
@MainActor
struct NewlineEditorTests {
    @Test func enterContinuesAListAndUndoRemovesIt() throws {
        let harness = NativeEditorHarness(text: "- a")
        defer { harness.teardown() }
        let textView = harness.textView!
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        harness.event { pressReturn(in: textView) }
        #expect(textView.string == "- a\n- ")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))

        textView.undoManager?.undo()
        #expect(textView.string == "- a")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
    }

    /// Enter on the empty item ends the list; each Enter is its own undo step.
    @Test func enterOnAnEmptyItemEndsTheList() throws {
        let harness = NativeEditorHarness(text: "- one")
        defer { harness.teardown() }
        let textView = harness.textView!
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        harness.event { pressReturn(in: textView) }
        harness.event { textView.insertText("two", replacementRange: textView.selectedRange()) }
        harness.event { pressReturn(in: textView) }
        harness.event { pressReturn(in: textView) }
        #expect(textView.string == "- one\n- two\n")

        textView.undoManager?.undo()
        #expect(textView.string == "- one\n- two\n- ")
        textView.undoManager?.undo()
        #expect(textView.string == "- one\n- two")
    }

    @Test func shiftEnterDoesNotContinue() {
        let harness = NativeEditorHarness(text: "- a")
        defer { harness.teardown() }
        let textView = harness.textView!
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        harness.event { pressReturn(in: textView, modifiers: .shift) }
        #expect(textView.string == "- a\n")
    }

    /// A plain line still gets AppKit's own newline.
    @Test func enterOnAPlainLineIsAnOrdinaryNewline() {
        let harness = NativeEditorHarness(text: "plain")
        defer { harness.teardown() }
        let textView = harness.textView!
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        harness.event { pressReturn(in: textView) }
        #expect(textView.string == "plain\n")
    }

    /// Sends a Return key-down through the window the way the event loop does,
    /// so `NSApp.currentEvent` is that event while the text view handles it.
    private func pressReturn(in textView: NSTextView, modifiers: NSEvent.ModifierFlags = []) {
        let window = textView.window!
        window.makeFirstResponder(textView)
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        )!
        NSApp.postEvent(event, atStart: true)
        let current = NSApp.nextEvent(matching: .keyDown, until: .distantPast, inMode: .default, dequeue: true)
        #expect(current?.keyCode == 36)
        window.sendEvent(current ?? event)
    }
}
#endif

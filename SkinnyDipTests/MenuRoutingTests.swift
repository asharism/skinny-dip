#if os(macOS)
import AppKit
import Testing
@testable import SkinnyDip

/// Edit menu Undo/Redo are sent down the responder chain by selector. A
/// misspelled selector compiles but nothing answers it, so the menu item does
/// nothing (⌘Z still works because CodeMirror handles the key itself).
@MainActor
struct MenuRoutingTests {
    @Test func editorWebViewIsAnEditorResponder() {
        let webView: AnyObject = EditorWebView(frame: .zero)
        #expect(webView is any EditorResponder)
    }

    @Test func editorAnswersMenuUndo() {
        #expect(EditorWebView.instancesRespond(to: CopyCommands.undoSelector))
    }

    @Test func editorAnswersMenuRedo() {
        #expect(EditorWebView.instancesRespond(to: CopyCommands.redoSelector))
    }

    @Test func nativeTextViewIsAnEditorResponder() {
        let textView: AnyObject = NativeEditorTextView(usingTextLayoutManager: true)
        #expect(textView is any EditorResponder)
    }

    @Test func nativeTextViewAnswersMenuUndoAndRedo() {
        #expect(NativeEditorTextView.instancesRespond(to: CopyCommands.undoSelector))
        #expect(NativeEditorTextView.instancesRespond(to: CopyCommands.redoSelector))
    }

    @Test func nativeMenuUndoAndRedoRouteToItsUndoManager() {
        let harness = NativeEditorHarness(text: "")
        defer { harness.teardown() }
        harness.event { harness.textView.insertText("typed", replacementRange: NSRange(location: 0, length: 0)) }
        #expect(NSApp.sendAction(CopyCommands.undoSelector, to: harness.textView, from: nil))
        #expect(harness.textView.string == "")
        #expect(NSApp.sendAction(CopyCommands.redoSelector, to: harness.textView, from: nil))
        #expect(harness.textView.string == "typed")
    }

    @Test func undoAndRedoSelectorsAreTheResponderMethods() {
        #expect(CopyCommands.undoSelector == NSSelectorFromString("skinnyDipUndo:"))
        #expect(CopyCommands.redoSelector == NSSelectorFromString("skinnyDipRedo:"))
    }
}
#endif

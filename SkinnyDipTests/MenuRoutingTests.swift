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

    @Test func undoAndRedoSelectorsAreTheResponderMethods() {
        #expect(CopyCommands.undoSelector == NSSelectorFromString("skinnyDipUndo:"))
        #expect(CopyCommands.redoSelector == NSSelectorFromString("skinnyDipRedo:"))
    }
}
#endif

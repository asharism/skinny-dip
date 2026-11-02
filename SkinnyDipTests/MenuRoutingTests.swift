#if os(macOS)
import AppKit
import Testing
@testable import SkinnyDip

/// Edit menu Undo/Redo are sent down the responder chain by selector. A
/// misspelled selector compiles but nothing answers it, so the menu item does
/// nothing (⌘Z still works because CodeMirror handles the key itself).
@MainActor
struct MenuRoutingTests {
    @Test func editorAnswersMenuUndo() {
        #expect(EditorWebView.instancesRespond(to: CopyCommands.undoSelector))
    }

    @Test func editorAnswersMenuRedo() {
        #expect(EditorWebView.instancesRespond(to: CopyCommands.redoSelector))
    }
}
#endif

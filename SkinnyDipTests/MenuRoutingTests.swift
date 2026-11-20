#if os(macOS)
import AppKit
import MarkdownCore
import SwiftUI
import Testing
@testable import SkinnyDip

/// Edit menu Undo/Redo are sent down the responder chain by selector. A
/// misspelled selector compiles but nothing answers it, so the menu item does
/// nothing.
@MainActor
struct MenuRoutingTests {
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

    // MARK: ADR-0012 Format menu

    /// The Format menu is installed for the Editing Commands, and hidden only
    /// while no feature has added an item to it.
    @Test func formatMenuIsInstalledAndHiddenWhileEmpty() throws {
        let item = try #require(NSApp.mainMenu?.items.first { $0.title == FormatCommands.menuTitle })
        let menu = try #require(item.submenu)
        FormatCommands.hideWhileEmpty()
        #expect(item.isHidden == menu.items.isEmpty)
    }

    // MARK: ADR-0011 copy commands

    @Test func editMenuHasPlainCopyRichTextAndHTMLButNoCopyAsMarkdown() throws {
        let editMenu = try #require(NSApp.mainMenu?.items.first { $0.title == "Edit" }?.submenu)
        let copy = try #require(editMenu.items.first { $0.title == "Copy" })
        #expect(copy.keyEquivalent.lowercased() == "c")
        #expect(copy.keyEquivalentModifierMask == .command)

        let rich = try #require(editMenu.items.first { $0.title == "Copy as Rich Text" })
        #expect(rich.keyEquivalent.lowercased() == "c")
        #expect(rich.keyEquivalentModifierMask.contains([.command, .shift]))
        #expect(!rich.keyEquivalentModifierMask.contains(.option))

        let html = try #require(editMenu.items.first { $0.title == "Copy as HTML" })
        #expect(html.keyEquivalent.lowercased() == "c")
        #expect(html.keyEquivalentModifierMask == [.command, .option])

        #expect(!editMenu.items.contains { $0.title == "Copy as Markdown" })
    }

    @Test func copyNeedsASelectionButRichTextOnlyANonEmptyDocument() {
        let noSelection = EditorPasteboardMenuState(editorHasSelection: false, documentIsEmpty: false, previewSelection: nil, canPaste: true)
        #expect(!noSelection.canCopy)
        #expect(!noSelection.canCut)
        #expect(noSelection.canCopyRichText)

        let selected = EditorPasteboardMenuState(editorHasSelection: true, documentIsEmpty: false, previewSelection: nil, canPaste: true)
        #expect(selected.canCopy)
        #expect(selected.canCut)
        #expect(selected.canCopyRichText)

        let empty = EditorPasteboardMenuState(editorHasSelection: false, documentIsEmpty: true, previewSelection: nil, canPaste: true)
        #expect(!empty.canCopy)
        #expect(!empty.canCopyRichText)
    }

    /// With the Preview focused, Copy follows the Preview's selection, not the editor's.
    @Test func copyFollowsThePreviewSelectionWhenThePreviewHasFocus() {
        let unselected = EditorPasteboardMenuState(editorHasSelection: true, documentIsEmpty: false, previewSelection: false, canPaste: true)
        #expect(!unselected.canCopy)
        #expect(!unselected.canCut)
        #expect(unselected.canCopyRichText)

        let selected = EditorPasteboardMenuState(editorHasSelection: false, documentIsEmpty: false, previewSelection: true, canPaste: true)
        #expect(selected.canCopy)
        #expect(!selected.canCut)
    }

    /// The Copy split button's ▾ menu shows ⇧⌘C and ⌥⌘C, but only the Edit menu
    /// may answer them, or one keystroke would copy twice from different sources.
    @Test func splitButtonMenuShortcutsAreNotLiveKeyEquivalents() throws {
        var fired: [String] = []
        let theme = ThemeStore().resolved(mode: ThemeSelection.matchSystem, fixed: ThemeSelection.defaultLight, light: ThemeSelection.defaultLight, dark: ThemeSelection.defaultDark, systemIsDark: false)
        let button = CopySplitButton(
            theme: theme, documentID: UUID(), empty: false, selection: false,
            copyRichText: { fired.append("rich") },
            copyMarkdown: { fired.append("markdown") },
            copyHTML: { fired.append("html") }
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        // A control: a plain button's shortcut in the same view does fire this way.
        let control = Button("Control") { fired.append("control") }.keyboardShortcut("k")
        window.contentView = NSHostingView(rootView: HStack { button; control })
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        window.displayIfNeeded()

        let keys: [(String, NSEvent.ModifierFlags, UInt16)] = [("C", [.command, .shift], 8), ("c", [.command, .option], 8), ("k", .command, 40)]
        for (characters, flags, keyCode) in keys {
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode
            ))
            _ = window.performKeyEquivalent(with: event)
        }
        #expect(fired == ["control"])
    }

    @Test func previewContextMenuOffersPlainCopyThenRichText() throws {
        let webView = PreviewWebView(frame: .zero)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: ""))
        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        webView.willOpenMenu(menu, with: event)
        #expect(menu.items.map(\.title) == ["Copy", "Copy as Rich Text"])
        #expect(menu.items[0].action == #selector(PreviewWebView.copy(_:)))
    }

    @Test func copyShortcutsMapToTheirCommands() throws {
        func key(_ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: 8
            ))
        }
        #expect(AppKeyboardShortcuts.copyCommand(for: try key("c", .command)) == .plain)
        #expect(AppKeyboardShortcuts.copyCommand(for: try key("C", [.command, .shift])) == .richText)
        #expect(AppKeyboardShortcuts.copyCommand(for: try key("c", [.command, .option])) == .html)
        #expect(AppKeyboardShortcuts.copyCommand(for: try key("x", .command)) == nil)
        #expect(AppKeyboardShortcuts.copyCommand(for: try key("c", .control)) == nil)
    }
}
#endif

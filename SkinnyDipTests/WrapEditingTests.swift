#if os(macOS)
import AppKit
import MarkdownCore
import Testing
@testable import SkinnyDip

/// Wrap (#93) in the native editor: typed pairs wrap a selection, paste
/// doesn't, and ⌘B / ⌘I reach the editor through the Format menu.
@MainActor
struct WrapEditingTests {
    private func key(_ characters: String, _ flags: NSEvent.ModifierFlags, keyCode: UInt16, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ))
    }

    @Test func typingStarOverSelectionWraps() throws {
        let harness = NativeEditorHarness(text: "a word 👋🏽")
        defer { harness.teardown() }
        let textView = harness.textView!
        let window = try #require(textView.window)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 4))

        // Shift-8 types `*` on a US layout.
        harness.event { window.sendEvent(try! key("*", .shift, keyCode: 28, window: window)) }
        #expect(textView.string == "a *word* 👋🏽")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 4))

        harness.event { window.sendEvent(try! key("*", .shift, keyCode: 28, window: window)) }
        #expect(textView.string == "a **word** 👋🏽")
        #expect(textView.selectedRange() == NSRange(location: 4, length: 4))

        // One undo step per key, each restoring the selection.
        textView.undoManager?.undo()
        #expect(textView.string == "a *word* 👋🏽")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 4))

        // A plain letter still replaces the selection.
        harness.event { window.sendEvent(try! key("x", [], keyCode: 7, window: window)) }
        #expect(textView.string == "a *x* 👋🏽")
    }

    @Test func pastingAStarOverSelectionReplaces() {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.wrap.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let harness = NativeEditorHarness(text: "a word b")
        defer { harness.teardown() }
        let textView = harness.textView!
        textView.pasteboard = pasteboard
        pasteboard.clearContents()
        pasteboard.setString("*", forType: .string)

        textView.setSelectedRange(NSRange(location: 2, length: 4))
        harness.event { textView.paste(nil) }
        #expect(textView.string == "a * b")
    }

    /// ⌘B and ⌘I as the menu sends them: the shortcut fires a main-menu item
    /// (the Format menu's, per the test below), whose action goes down the
    /// focused window's responder chain. A hosted test window can't become key
    /// while the test runner is in front, so the chain is walked from the
    /// window's first responder rather than through `NSApp.keyWindow`.
    @Test func commandBTogglesBold() throws {
        let harness = NativeEditorHarness(text: "a word b")
        defer { harness.teardown() }
        let textView = harness.textView!
        let window = try #require(textView.window)
        let mainMenu = try #require(NSApp.mainMenu)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 2, length: 4))

        func press(_ letter: String, keyCode: UInt16, _ action: Selector) throws {
            #expect(mainMenu.performKeyEquivalent(with: try key(letter, .command, keyCode: keyCode, window: window)))
            harness.event { #expect(window.firstResponder?.tryToPerform(action, with: nil) == true) }
        }

        try press("b", keyCode: 11, WrapCommands.boldSelector)
        #expect(textView.string == "a **word** b")
        #expect(textView.selectedRange() == NSRange(location: 4, length: 4))

        try press("b", keyCode: 11, WrapCommands.boldSelector)
        #expect(textView.string == "a word b")
        #expect(textView.selectedRange() == NSRange(location: 2, length: 4))

        try press("i", keyCode: 34, WrapCommands.italicSelector)
        #expect(textView.string == "a *word* b")

        // ⌘Z steps back one command at a time, restoring the selection.
        textView.undoManager?.undo()
        #expect(textView.string == "a word b")
        textView.undoManager?.undo()
        #expect(textView.string == "a **word** b")
        #expect(textView.selectedRange() == NSRange(location: 4, length: 4))
    }

    /// Nothing else in the menu bar claims ⌘B or ⌘I (no Font menu's Bold).
    @Test func boldAndItalicShortcutsBelongToTheFormatMenu() throws {
        let mainMenu = try #require(NSApp.mainMenu)
        func items(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) }
        }
        let all = items(mainMenu)
        for (letter, title) in [("b", "Bold"), ("i", "Italic")] {
            let claimed = all.filter { $0.keyEquivalent == letter && $0.keyEquivalentModifierMask == .command }
            #expect(claimed.map(\.title) == [title])
        }
        let format = try #require(mainMenu.items.first { $0.title == FormatCommands.menuTitle }?.submenu)
        #expect(format.items.contains { $0.title == "Bold" })
        #expect(format.items.contains { $0.title == "Italic" })
    }
}
#endif

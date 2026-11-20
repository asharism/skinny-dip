#if os(macOS)
import AppKit
import MarkdownCore
import Testing
@testable import SkinnyDip

/// Tab / ⇧Tab and ⌘] / ⌘[ (#91) through the real key path: key events sent to
/// the editor's window, not direct method calls, so the bindings are proven.
@MainActor
struct IndentEditorTests {
    private func key(_ characters: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ))
    }

    private func tab(_ harness: NativeEditorHarness) throws {
        let window = try #require(harness.textView.window)
        let event = try key("\t", keyCode: 48, in: window)
        harness.event { window.sendEvent(event) }
    }

    /// `grouped: false` sends it outside an undo group, for a key that must
    /// register no undo (registering with no open group would raise).
    private func shiftTab(_ harness: NativeEditorHarness, grouped: Bool = true) throws {
        let window = try #require(harness.textView.window)
        let event = try key("\u{19}", keyCode: 48, flags: .shift, in: window)
        if grouped { harness.event { window.sendEvent(event) } } else { window.sendEvent(event) }
    }

    @Test func tabIndentsAListItemAndShiftTabOutdents() throws {
        let harness = NativeEditorHarness(text: "- a\n- b")
        defer { harness.teardown() }
        let textView = harness.textView!
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        try tab(harness)
        #expect(textView.string == "- a\n  - b")
        #expect(textView.selectedRange() == NSRange(location: 9, length: 0))

        try shiftTab(harness)
        #expect(textView.string == "- a\n- b")
        #expect(textView.selectedRange() == NSRange(location: 7, length: 0))

        // ⇧Tab with no indent changes nothing and leaves no undo step.
        try shiftTab(harness, grouped: false)
        #expect(textView.string == "- a\n- b")
        #expect(textView.selectedRange() == NSRange(location: 7, length: 0))

        textView.undoManager?.undo()
        #expect(textView.string == "- a\n  - b")
        #expect(textView.selectedRange() == NSRange(location: 9, length: 0))
        textView.undoManager?.undo()
        #expect(textView.string == "- a\n- b")
        #expect(textView.selectedRange() == NSRange(location: 7, length: 0))
        #expect(textView.undoManager?.canUndo == false)
    }

    @Test func tabNeverInsertsATabCharacter() throws {
        let harness = NativeEditorHarness(text: "ab\n\n```\ncode\n```")
        defer { harness.teardown() }
        let textView = harness.textView!
        textView.window?.makeFirstResponder(textView)

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        try tab(harness)
        #expect(textView.string == "ab  \n\n```\ncode\n```")

        // A selection of a blank line: handled, not replaced by a tab.
        textView.setSelectedRange(NSRange(location: 5, length: 1))
        try tab(harness)
        #expect(!textView.string.contains("\t"))

        // Inside fenced code too.
        let code = (textView.string as NSString).range(of: "code")
        textView.setSelectedRange(NSRange(location: code.location, length: 0))
        try tab(harness)
        #expect(textView.string == "ab  \n\n```\n    code\n```")

        // A multi-line selection indents every line, in one undo step.
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        try tab(harness)
        #expect(!textView.string.contains("\t"))
        #expect(textView.string.hasPrefix("    ab  \n\n    ```"))
        textView.undoManager?.undo()
        #expect(textView.string == "ab  \n\n```\n    code\n```")
    }

    @Test func formatMenuIndentAndOutdentUseCommandBrackets() throws {
        let menu = try #require(NSApp.mainMenu?.items.first { $0.title == FormatCommands.menuTitle }?.submenu)
        let indent = try #require(menu.items.first { $0.title == "Indent" })
        #expect(indent.keyEquivalent == "]")
        #expect(indent.keyEquivalentModifierMask == .command)
        let outdent = try #require(menu.items.first { $0.title == "Outdent" })
        #expect(outdent.keyEquivalent == "[")
        #expect(outdent.keyEquivalentModifierMask == .command)

        // No other menu item claims ⌘] or ⌘[ (⇧⌘] and ⇧⌘[ switch Tabs).
        func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }
        let claims = items(try #require(NSApp.mainMenu)).filter {
            ($0.keyEquivalent == "]" || $0.keyEquivalent == "[") && $0.keyEquivalentModifierMask == .command
        }
        #expect(claims.map(\.title).sorted() == ["Indent", "Outdent"])
    }

    @Test func commandBracketsIndentAndOutdentThroughTheMenu() throws {
        let harness = NativeEditorHarness(text: "one\ntwo\nthree")
        defer { harness.teardown() }
        let textView = harness.textView!
        let window = try #require(textView.window)
        window.makeFirstResponder(textView)
        let mainMenu = try #require(NSApp.mainMenu)
        textView.setSelectedRange(NSRange(location: 1, length: 9))

        let indent = try key("]", keyCode: 30, flags: .command, in: window)
        var handled = false
        harness.event { handled = mainMenu.performKeyEquivalent(with: indent) }
        #expect(handled)
        // The menu sends its selector to the key window's first responder. A
        // hosted test app isn't active, so its key window isn't this one: deliver
        // the selector to the editor the way the responder chain would.
        harness.event { #expect(NSApp.sendAction(#selector(NativeEditorTextView.skinnyDipIndent(_:)), to: textView, from: nil)) }
        #expect(textView.string == "    one\n    two\n    three")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 25))

        textView.undoManager?.undo()
        #expect(textView.string == "one\ntwo\nthree")

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        harness.event { textView.insertText("    ", replacementRange: NSRange(location: 0, length: 0)) }
        let outdent = try key("[", keyCode: 33, flags: .command, in: window)
        harness.event { handled = mainMenu.performKeyEquivalent(with: outdent) }
        #expect(handled)
        harness.event { #expect(NSApp.sendAction(#selector(NativeEditorTextView.skinnyDipOutdent(_:)), to: textView, from: nil)) }
        #expect(textView.string == "one\ntwo\nthree")
    }
}
#endif

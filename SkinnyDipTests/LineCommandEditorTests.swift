#if os(macOS)
import AppKit
import MarkdownCore
import Testing
@testable import SkinnyDip

/// Line commands (#92) through the real key path: a key event sent through the
/// window is claimed by the focused editor's `performKeyEquivalent` before its
/// own ⌥↑/⌥↓ key bindings run.
extension NativeEditorTests {
    @Test func optionArrowsMoveLinesAsOneUndoStep() throws {
        let harness = NativeEditorHarness(text: "- one\n- two\n- three")
        defer { harness.teardown() }
        let textView = try harness.focus()
        let undoManager = try #require(textView.undoManager)

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        harness.event { harness.press(.downArrow, .option) }
        #expect(textView.string == "- two\n- one\n- three")
        #expect(textView.selectedRange() == NSRange(location: 9, length: 0))

        harness.event { harness.press(.downArrow, .option) }
        #expect(textView.string == "- two\n- three\n- one")
        #expect(textView.selectedRange() == NSRange(location: 17, length: 0))

        // At the bottom: nothing changes and no undo step (the
        // undo count below proves it), so no undo group around it either.
        harness.press(.downArrow, .option)
        #expect(textView.string == "- two\n- three\n- one")

        harness.event { harness.press(.upArrow, .option) }
        #expect(textView.string == "- two\n- one\n- three")
        #expect(textView.selectedRange() == NSRange(location: 9, length: 0))

        undoManager.undo()
        #expect(textView.string == "- two\n- three\n- one")
        #expect(textView.selectedRange() == NSRange(location: 17, length: 0))
        undoManager.undo()
        undoManager.undo()
        #expect(textView.string == "- one\n- two\n- three")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
        #expect(!undoManager.canUndo)
    }

    @Test func shiftOptionArrowsDuplicateAndCommandShiftKDeletes() throws {
        let harness = NativeEditorHarness(text: "a\nb")
        defer { harness.teardown() }
        let textView = try harness.focus()

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        harness.event { harness.press(.downArrow, [.option, .shift]) }
        #expect(textView.string == "a\na\nb")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

        harness.event { harness.press(.upArrow, [.option, .shift]) }
        #expect(textView.string == "a\na\na\nb")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

        harness.event { harness.press("K", [.command, .shift], keyCode: 40) }
        #expect(textView.string == "a\na\nb")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

        textView.undoManager?.undo()
        #expect(textView.string == "a\na\na\nb")
    }

    @Test func commandLSelectsAndExtends() throws {
        let harness = NativeEditorHarness(text: "one\ntwo\nthree")
        defer { harness.teardown() }
        let textView = try harness.focus()

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        harness.press("l", .command, keyCode: 37)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 4))
        harness.press("l", .command, keyCode: 37)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 8))
        #expect(textView.undoManager?.canUndo == false)
        #expect(textView.string == "one\ntwo\nthree")
    }
}

extension MenuRoutingTests {
    @Test func formatMenuHasTheLineCommands() throws {
        let menu = try #require(NSApp.mainMenu?.items.first { $0.title == FormatCommands.menuTitle }?.submenu)
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let expected: [(String, String, NSEvent.ModifierFlags, Selector)] = [
            ("Move Line Up", up, .option, #selector(NativeEditorTextView.moveLinesUp(_:))),
            ("Move Line Down", down, .option, #selector(NativeEditorTextView.moveLinesDown(_:))),
            ("Duplicate Line Up", up, [.option, .shift], #selector(NativeEditorTextView.duplicateLinesUp(_:))),
            ("Duplicate Line Down", down, [.option, .shift], #selector(NativeEditorTextView.duplicateLinesDown(_:))),
            ("Delete Line", "k", [.command, .shift], #selector(NativeEditorTextView.deleteLines(_:))),
            ("Select Line", "l", .command, #selector(NSResponder.selectLine(_:))),
        ]
        for (title, key, modifiers, action) in expected {
            let item = try #require(menu.items.first { $0.title == title }, "\(title)")
            #expect(item.keyEquivalent.lowercased() == key, "\(title)")
            let mask = item.keyEquivalentModifierMask.intersection([.command, .option, .shift, .control])
            #expect(mask == modifiers, "\(title)")
            // The focused editor claims the same key for the same command.
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: mask, timestamp: 0, windowNumber: 0, context: nil,
                characters: item.keyEquivalent, charactersIgnoringModifiers: item.keyEquivalent, isARepeat: false, keyCode: 0
            ))
            #expect(NativeEditorTextView.lineCommand(for: event) == action, "\(title)")
        }
    }

    /// Unfocused, the editor leaves ⌥↓ alone, so it never acts on a hidden selection.
    @Test func lineCommandShortcutsNeedEditorFocus() throws {
        let harness = NativeEditorHarness(text: "a\nb")
        defer { harness.teardown() }
        let textView = try #require(harness.textView)
        textView.window?.makeFirstResponder(nil)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.option, .numericPad, .function], timestamp: 0,
            windowNumber: textView.window?.windowNumber ?? 0, context: nil, characters: down,
            charactersIgnoringModifiers: down, isARepeat: false, keyCode: 125
        ))
        #expect(!textView.performKeyEquivalent(with: event))
        #expect(textView.string == "a\nb")
    }
}

extension NativeEditorHarness {
    /// Focuses the editor in the harness window.
    func focus() throws -> NativeEditorTextView {
        let textView = try #require(textView)
        let window = try #require(textView.window)
        #expect(window.makeFirstResponder(textView))
        return textView
    }

    enum Arrow { case upArrow, downArrow }

    func press(_ arrow: Arrow, _ flags: NSEvent.ModifierFlags) {
        let (character, keyCode): (Int, UInt16) = arrow == .upArrow ? (NSUpArrowFunctionKey, 126) : (NSDownArrowFunctionKey, 125)
        press(String(UnicodeScalar(character)!), flags.union([.numericPad, .function]), keyCode: keyCode)
    }

    /// Sends a key-down through the window: key equivalents first, then the
    /// first responder's `keyDown` (AppKit's own key bindings) if none claims it.
    func press(_ characters: String, _ flags: NSEvent.ModifierFlags, keyCode: UInt16) {
        guard let window = textView.window, let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters.lowercased(), isARepeat: false, keyCode: keyCode
        ) else { return }
        // The window isn't key in a hosted test (the app isn't active), so do
        // what NSApp does for the key window: key equivalents, then keyDown.
        if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
    }
}
#endif

#if os(macOS)
import AppKit
import MarkdownCore
import Testing
@testable import SkinnyDip

/// Links (#94), driven through the app's real main menu: each key finds the
/// menu item bound to it, whose command then runs on the editor.
@MainActor
@Suite(.serialized)
struct NativeEditorLinkTests {
    @Test func pastingAURLOverASelectionMakesALink() throws {
        let (harness, pasteboard) = makeEditor("See the docs now")
        defer { teardown(harness, pasteboard) }
        harness.textView.setSelectedRange(NSRange(location: 4, length: 8))
        MacClipboard(pasteboard: pasteboard).write(plainText: "https://example.com/a?b=1")

        harness.event { press("v", .command, in: harness) }
        #expect(harness.textView.string == "See [the docs](https://example.com/a?b=1) now")
        #expect(harness.textView.selectedRange() == NSRange(location: 41, length: 0))

        // One undo step, back to the word and its selection.
        harness.textView.skinnyDipUndo(nil)
        #expect(harness.textView.string == "See the docs now")
        #expect(harness.textView.selectedRange() == NSRange(location: 4, length: 8))
    }

    @Test func plainPasteDoesNotLink() throws {
        let (harness, pasteboard) = makeEditor("See docs")
        defer { teardown(harness, pasteboard) }
        harness.textView.setSelectedRange(NSRange(location: 4, length: 4))
        MacClipboard(pasteboard: pasteboard).write(plainText: "https://example.com")

        harness.event { press("v", [.command, .option, .shift], in: harness) }
        #expect(harness.textView.string == "See https://example.com")
    }

    @Test func pastingAURLWithNoSelectionPastesTheURL() throws {
        let (harness, pasteboard) = makeEditor("See ")
        defer { teardown(harness, pasteboard) }
        harness.textView.setSelectedRange(NSRange(location: 4, length: 0))
        MacClipboard(pasteboard: pasteboard).write(plainText: "https://example.com")

        harness.event { press("v", .command, in: harness) }
        #expect(harness.textView.string == "See https://example.com")
    }

    @Test func commandKUsesTheClipboardURL() throws {
        let (harness, pasteboard) = makeEditor("a word b")
        defer { teardown(harness, pasteboard) }
        harness.textView.setSelectedRange(NSRange(location: 2, length: 4))
        MacClipboard(pasteboard: pasteboard).write(plainText: "https://x.y/(z)")

        harness.event { press("k", .command, in: harness) }
        #expect(harness.textView.string == "a [word](<https://x.y/(z)>) b")
        #expect(harness.textView.selectedRange() == NSRange(location: 27, length: 0))
        harness.textView.skinnyDipUndo(nil)
        #expect(harness.textView.string == "a word b")
        #expect(harness.textView.selectedRange() == NSRange(location: 2, length: 4))

        // No URL on the clipboard: the caret waits in the parens.
        MacClipboard(pasteboard: pasteboard).write(plainText: "not a url")
        harness.event { press("k", .command, in: harness) }
        #expect(harness.textView.string == "a [word]() b")
        #expect(harness.textView.selectedRange() == NSRange(location: 9, length: 0))
    }

    @Test func formatMenuHasLinkOnCommandK() throws {
        let format = try #require(NSApp.mainMenu?.items.first { $0.title == FormatCommands.menuTitle }?.submenu)
        let link = try #require(format.items.first { $0.title == "Link" })
        #expect(link.keyEquivalent == "k")
        #expect(link.keyEquivalentModifierMask == .command)
    }

    // MARK: Helpers

    private func makeEditor(_ text: String) -> (NativeEditorHarness, NSPasteboard) {
        let pasteboard = NSPasteboard(name: .init("SkinnyDipTests.links.\(UUID().uuidString)"))
        let harness = NativeEditorHarness(text: text)
        harness.textView.pasteboard = pasteboard
        return (harness, pasteboard)
    }

    private func teardown(_ harness: NativeEditorHarness, _ pasteboard: NSPasteboard) {
        harness.teardown()
        pasteboard.releaseGlobally()
    }

    /// Presses a key: finds the app's main-menu item AppKit would pick for it,
    /// then sends that item's command to the editor. The test host can't make
    /// its window key (it never becomes the active app), so this stands in for
    /// the key window's responder chain, the one step AppKit owns.
    private func press(_ key: String, _ flags: NSEvent.ModifierFlags, in harness: NativeEditorHarness) {
        guard let item = NSApp.mainMenu.flatMap({ Self.item(for: key, flags, in: $0) }) else {
            Issue.record("no main-menu item answers \(flags) \(key)")
            return
        }
        let textView = harness.textView!
        switch item.title {
        // `CopyCommands.paste()` / `pasteAsPlainText()` with the editor active.
        case "Paste as Markdown": textView.insertMarkdownFromPasteboard(plain: false)
        case "Paste and Match Style": textView.insertMarkdownFromPasteboard(plain: true)
        // `FormatCommands` sends this selector down the responder chain.
        case "Link": #expect(NSApp.sendAction(#selector(NativeEditorTextView.skinnyDipInsertLink(_:)), to: textView, from: item))
        default: Issue.record("unexpected menu item \(item.title)")
        }
    }

    /// The menu item whose key equivalent is `key` with exactly `flags`; an
    /// uppercase key equivalent implies ⇧, as AppKit reads it.
    private static func item(for key: String, _ flags: NSEvent.ModifierFlags, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if let submenu = item.submenu, let found = Self.item(for: key, flags, in: submenu) { return found }
            guard !item.keyEquivalent.isEmpty, item.keyEquivalent.lowercased() == key else { continue }
            var mask = item.keyEquivalentModifierMask.intersection([.command, .option, .shift, .control])
            if item.keyEquivalent != item.keyEquivalent.lowercased() { mask.insert(.shift) }
            if mask == flags { return item }
        }
        return nil
    }
}
#endif

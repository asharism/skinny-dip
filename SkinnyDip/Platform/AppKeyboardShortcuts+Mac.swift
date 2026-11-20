#if os(macOS)
import AppKit

/// WKWebView claims many ⌘ shortcuts in `performKeyEquivalent` without running them.
enum AppKeyboardShortcuts {
    /// Returns `true` when the event was handled (e.g. Quit).
    static func performMainMenuShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return false }
        guard event.charactersIgnoringModifiers?.lowercased() == "q" else { return false }
        return NSApp.sendAction(#selector(NSApplication.terminate(_:)), to: NSApp, from: NSApp)
    }

    /// ⌘? (⇧⌘/) opens the Help menu's search. The focused Preview's WKWebView
    /// claims it without running it, so the Preview leaves it to the menu bar.
    static func isHelpSearch(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers
        return (key == "?" || key == "/") && (flags == .command || flags == [.command, .shift])
    }

    /// The Preview web view claims ⌘C itself so
    /// WebKit's styled copy never runs: ⌘C plain, ⌘⇧C rich text, ⌥⌘C HTML (ADR-0011).
    static func copyCommand(for event: NSEvent) -> CopyCommand? {
        guard event.type == .keyDown,
              event.charactersIgnoringModifiers?.lowercased() == "c"
        else { return nil }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch flags {
        case .command: return .plain
        case [.command, .shift]: return .richText
        case [.command, .option]: return .html
        default: return nil
        }
    }
}
#endif

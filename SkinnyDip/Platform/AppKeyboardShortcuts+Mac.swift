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
}
#endif

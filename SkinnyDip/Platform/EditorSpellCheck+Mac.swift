#if os(macOS)
import AppKit

enum EditorSpellCheck {
    /// Prime the shared spell checker so WebKit underlines appear promptly (MarkEdit `EditorWindowController`).
    static func warmUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            _ = NSSpellChecker.shared.checkSpelling(of: "warmup", startingAt: 0)
        }
    }
}
#endif

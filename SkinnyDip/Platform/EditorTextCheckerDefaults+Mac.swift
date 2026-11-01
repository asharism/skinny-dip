#if os(macOS)
import Foundation

/// WebKit reads these from `UserDefaults`, and missing keys mean **off**.
/// Autocorrect can still be on via the system while red underlines stay off.
/// See WebKit `TextCheckerMac.mm` (`WebContinuousSpellCheckingEnabled`).
enum EditorTextCheckerDefaults {
    static let keys = [
        "NSAllowContinuousSpellChecking",
        "WebContinuousSpellCheckingEnabled",
        "WebGrammarCheckingEnabled",
        "WebAutomaticSpellingCorrectionEnabled",
        "WebAutomaticTextReplacementEnabled",
    ]

    static func enable() {
        let defaults = UserDefaults.standard
        for key in keys {
            defaults.set(true, forKey: key)
        }
    }
}
#endif

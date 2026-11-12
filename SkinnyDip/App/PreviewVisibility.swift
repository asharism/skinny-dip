import Foundation

/// Whether a Tab opens with its Preview Card shown. Settings › General sets the
/// default for new documents; ⇧⌘P and the Show/Hide Preview buttons then toggle
/// only the current Tab.
enum PreviewVisibility {
    /// Settings › General › "Show Preview in new documents". Unset means shown.
    static let inNewDocuments = "previewInNewDocuments"
    /// Before 0.1.5 one global key hid the Preview in every Window.
    static let legacyShowPreview = "showPreview"

    static func initial(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: inNewDocuments) as? Bool ?? true
    }

    /// Someone who kept the Preview hidden keeps opening documents without it.
    static func migrate(_ defaults: UserDefaults = .standard) {
        guard let legacy = defaults.object(forKey: legacyShowPreview) as? Bool else { return }
        if legacy == false, defaults.object(forKey: inNewDocuments) == nil {
            defaults.set(false, forKey: inNewDocuments)
        }
        defaults.removeObject(forKey: legacyShowPreview)
    }
}

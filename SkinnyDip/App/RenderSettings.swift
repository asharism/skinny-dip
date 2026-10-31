import Foundation
import MarkdownCore

/// The `UserDefaults` keys behind the Settings toggles. An unset key means the
/// option's value in `RenderOptions.default`, so a fresh install copies with
/// the out-of-the-box settings without registering defaults.
enum RenderSettings {
    static let demotesHeadings = "demotesHeadings"
    static let bordersTables = "bordersTables"
    static let newlinesAsBreaks = "newlinesAsBreaks"

    static func options(from defaults: UserDefaults = .standard) -> RenderOptions {
        let fallback = RenderOptions.default
        return RenderOptions(
            demotesHeadings: defaults.object(forKey: demotesHeadings) as? Bool ?? fallback.demotesHeadings,
            bordersTables: defaults.object(forKey: bordersTables) as? Bool ?? fallback.bordersTables,
            newlinesAsBreaks: defaults.object(forKey: newlinesAsBreaks) as? Bool ?? fallback.newlinesAsBreaks
        )
    }
}

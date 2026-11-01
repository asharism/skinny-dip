import Foundation

/// Which theme file is active. Unknown ids fall back to Paper or Ink.
public enum ThemeSelection {
    public static let matchSystem = "system"
    public static let fixed = "fixed"
    public static let defaultLight = "paper"
    public static let defaultDark = "ink"

    public static func resolve(
        mode: String,
        fixed: String,
        light: String,
        dark: String,
        systemIsDark: Bool,
        available: Set<String>
    ) -> String {
        func known(_ id: String, fallback: String) -> String {
            available.contains(id) ? id : fallback
        }
        if mode == Self.fixed {
            return known(fixed, fallback: defaultLight)
        }
        return systemIsDark ? known(dark, fallback: defaultDark) : known(light, fallback: defaultLight)
    }
}

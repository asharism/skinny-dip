import Foundation

/// A color channel value in the range 0...1. Themes store hex in JSON; the
/// resolved tokens the window paints are `RGBA`, including alpha for surfaces.
public struct RGBA: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Parses `#rrggbb`. Anything else becomes opaque black.
    public init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        if text.count >= 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0
            g = 0
            b = 0
        }
        a = 1
    }

    public func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: alpha)
    }

    /// `fraction` is the weight of `other`. A 62/38 foreground/background mix is
    /// `foreground.mixed(with: background, fraction: 0.38)`.
    public func mixed(with other: RGBA, fraction: Double) -> RGBA {
        let t = min(1, max(0, fraction))
        func mix(_ lhs: Double, _ rhs: Double) -> Double { lhs * (1 - t) + rhs * t }
        return RGBA(r: mix(r, other.r), g: mix(g, other.g), b: mix(b, other.b), a: mix(a, other.a))
    }

    /// Source-over this color onto an opaque background.
    public func composited(over background: RGBA) -> RGBA {
        let alpha = a
        return RGBA(
            r: r * alpha + background.r * (1 - alpha),
            g: g * alpha + background.g * (1 - alpha),
            b: b * alpha + background.b * (1 - alpha),
            a: 1
        )
    }

    /// WCAG 2.x relative luminance of the RGB channels.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    /// WCAG 2.x contrast ratio. Callers composite translucent colors first.
    public static func contrast(_ lhs: RGBA, _ rhs: RGBA) -> Double {
        let lighter = max(lhs.relativeLuminance, rhs.relativeLuminance)
        let darker = min(lhs.relativeLuminance, rhs.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    public var css: String {
        if a >= 0.999 {
            return String(format: "#%02x%02x%02x", Self.byte(r), Self.byte(g), Self.byte(b))
        }
        return String(format: "rgba(%d, %d, %d, %.3f)", Self.byte(r), Self.byte(g), Self.byte(b), a)
    }

    private static func byte(_ channel: Double) -> Int {
        Int((min(1, max(0, channel)) * 255).rounded())
    }
}

/// One theme file from `SkinnyDip/Resources/themes`. Rex's terminal palette shape
/// plus an optional `skinnyDip` block (ADR-0005).
public struct ThemeFile: Decodable, Equatable, Sendable {
    public enum Appearance: String, Decodable, Equatable, Sendable {
        case light
        case dark
    }

    public struct SkinnyDip: Decodable, Equatable, Sendable {
        public var windowGradient: [String]
        public var muted: String?
        public var accent: String?
    }

    public var id: String
    public var name: String
    public var appearance: Appearance
    public var pair: String
    public var background: String
    public var foreground: String
    public var cursor: String
    public var cursorText: String
    public var selectionBackground: String
    public var selectionForeground: String
    public var ansi: [String]
    public var skinnyDip: SkinnyDip?

    public func resolve() -> ResolvedTheme {
        let backgroundColor = RGBA(hex: background)
        let foregroundColor = RGBA(hex: foreground)
        let gradient: [RGBA]
        if let stops = skinnyDip?.windowGradient, stops.count >= 2 {
            gradient = [RGBA(hex: stops[0]), RGBA(hex: stops[1])]
        } else {
            gradient = [backgroundColor, backgroundColor]
        }
        let muted = skinnyDip?.muted.map { RGBA(hex: $0) }
            ?? foregroundColor.mixed(with: backgroundColor, fraction: 0.38)
        let accent = skinnyDip?.accent.map { RGBA(hex: $0) } ?? RGBA(hex: cursor)
        let light = appearance == .light
        let white = RGBA(hex: "#ffffff")
        let black = RGBA(hex: "#000000")
        let ink = light ? black : white
        let paper = light ? white : white
        return ResolvedTheme(
            appearance: appearance,
            windowGradient: gradient,
            foreground: foregroundColor,
            muted: muted,
            accent: accent,
            selection: RGBA(hex: selectionBackground),
            heading: ansiColor(4, fallback: foregroundColor),
            marker: ansiColor(8, fallback: foregroundColor),
            emphasis: ansiColor(5, fallback: foregroundColor),
            link: ansiColor(6, fallback: foregroundColor),
            code: ansiColor(2, fallback: foregroundColor),
            quote: muted,
            onAccent: light ? RGBA(hex: "#ffffff") : RGBA(hex: "#121212"),
            card: paper.withAlpha(light ? 0.80 : 0.045),
            border: ink.withAlpha(light ? 0.08 : 0.09),
            border2: ink.withAlpha(light ? 0.16 : 0.22),
            strip: ink.withAlpha(light ? 0.055 : 0.06),
            tab: white.withAlpha(light ? 0.95 : 0.11),
            menu: light ? RGBA(hex: "#ffffff") : RGBA(hex: "#262a31"),
            codeBg: ink.withAlpha(light ? 0.05 : 0.07),
            cursor: RGBA(hex: cursor),
            shadows: light
                ? [
                    Shadow(x: 0, y: 1, blur: 2, color: black.withAlpha(0.05)),
                    Shadow(x: 0, y: 8, blur: 24, color: black.withAlpha(0.06)),
                ]
                : [Shadow(x: 0, y: 1, blur: 2, color: black.withAlpha(0.30))]
        )
    }

    private func ansiColor(_ index: Int, fallback: RGBA) -> RGBA {
        guard ansi.indices.contains(index) else { return fallback }
        return RGBA(hex: ansi[index])
    }
}

public struct Shadow: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var blur: Double
    public var color: RGBA

    public init(x: Double, y: Double, blur: Double, color: RGBA) {
        self.x = x
        self.y = y
        self.blur = blur
        self.color = color
    }
}

/// Every semantic role and surface the shell paints. Surface colors carry alpha.
public struct ResolvedTheme: Equatable, Sendable {
    public var appearance: ThemeFile.Appearance
    public var windowGradient: [RGBA]
    public var foreground: RGBA
    public var muted: RGBA
    public var accent: RGBA
    public var selection: RGBA
    public var heading: RGBA
    public var marker: RGBA
    public var emphasis: RGBA
    public var link: RGBA
    public var code: RGBA
    public var quote: RGBA
    public var onAccent: RGBA
    public var card: RGBA
    public var border: RGBA
    public var border2: RGBA
    public var strip: RGBA
    public var tab: RGBA
    public var menu: RGBA
    public var codeBg: RGBA
    public var cursor: RGBA
    public var shadows: [Shadow]

    public init(
        appearance: ThemeFile.Appearance,
        windowGradient: [RGBA],
        foreground: RGBA,
        muted: RGBA,
        accent: RGBA,
        selection: RGBA,
        heading: RGBA,
        marker: RGBA,
        emphasis: RGBA,
        link: RGBA,
        code: RGBA,
        quote: RGBA,
        onAccent: RGBA,
        card: RGBA,
        border: RGBA,
        border2: RGBA,
        strip: RGBA,
        tab: RGBA,
        menu: RGBA,
        codeBg: RGBA,
        cursor: RGBA,
        shadows: [Shadow]
    ) {
        self.appearance = appearance
        self.windowGradient = windowGradient
        self.foreground = foreground
        self.muted = muted
        self.accent = accent
        self.selection = selection
        self.heading = heading
        self.marker = marker
        self.emphasis = emphasis
        self.link = link
        self.code = code
        self.quote = quote
        self.onAccent = onAccent
        self.card = card
        self.border = border
        self.border2 = border2
        self.strip = strip
        self.tab = tab
        self.menu = menu
        self.codeBg = codeBg
        self.cursor = cursor
        self.shadows = shadows
    }

    /// CSS variables both web views receive. Keys are exact.
    public func cssVariables() -> [String: String] {
        [
            "--fg": foreground.css,
            "--muted": muted.css,
            "--accent": accent.css,
            "--selection": selection.css,
            "--heading": heading.css,
            "--marker": marker.css,
            "--emphasis": emphasis.css,
            "--link": link.css,
            "--code": code.css,
            "--quote": quote.css,
            "--border": border.css,
            "--border2": border2.css,
            "--code-bg": codeBg.css,
            "--cursor": cursor.css,
        ]
    }
}

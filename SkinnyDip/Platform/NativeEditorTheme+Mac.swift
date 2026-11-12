#if os(macOS)
import AppKit
import MarkdownCore

/// The native Editor Backend reads the same theme variables CodeMirror gets
/// (`ResolvedTheme.cssVariables()` plus font size, inline padding and Zoom).
struct NativeEditorTheme: Equatable {
    var foreground: NSColor
    var muted: NSColor
    var cursor: NSColor
    var selection: NSColor
    var roles: [HighlightRole: NSColor]
    var fontSize: CGFloat
    var inlinePadding: CGFloat
    var zoom: CGFloat

    init(vars: [String: String]) {
        func color(_ key: String, _ fallback: NSColor) -> NSColor {
            vars[key].flatMap(Self.color(css:)) ?? fallback
        }
        foreground = color("--fg", .textColor)
        muted = color("--muted", .secondaryLabelColor)
        cursor = color("--cursor", .controlAccentColor)
        selection = color("--selection", .selectedTextBackgroundColor)
        let emphasis = color("--emphasis", foreground)
        roles = [
            .heading: color("--heading", foreground),
            .marker: color("--marker", muted),
            .emphasis: emphasis,
            .strong: emphasis,
            .link: color("--link", foreground),
            .code: color("--code", foreground),
            .quote: color("--quote", foreground),
        ]
        zoom = vars["--zoom"].flatMap(Self.number) ?? 1
        fontSize = vars["--editor-font-size"].flatMap(Self.number) ?? 13 * zoom
        inlinePadding = vars["--editor-inline-pad"].flatMap(Self.number) ?? 22 * zoom
    }

    func color(for role: HighlightRole) -> NSColor {
        roles[role] ?? foreground
    }

    var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// CodeMirror's `.cm-content` padding: 8 above and 16 below (times Zoom),
    /// the inline padding at the sides.
    var insets: (horizontal: CGFloat, top: CGFloat, bottom: CGFloat) {
        (inlinePadding, 8 * zoom, 16 * zoom)
    }

    /// Line height 1.65, as in the CodeMirror Card.
    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let height = (fontSize * 1.65).rounded()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: foreground,
            .paragraphStyle: paragraphStyle,
        ]
    }

    /// `#rrggbb`, `#rgb` or `rgba(r, g, b, a)`, as `RGBA.css` writes them.
    static func color(css: String) -> NSColor? {
        let text = css.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { return NSColor(RGBA(hex: text)) }
        guard text.hasPrefix("rgb"), let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else {
            return nil
        }
        let parts = text[text.index(after: open)..<close]
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return NSColor(
            srgbRed: parts[0] / 255,
            green: parts[1] / 255,
            blue: parts[2] / 255,
            alpha: parts.count > 3 ? parts[3] : 1
        )
    }

    private static func number(_ text: String) -> CGFloat? {
        let digits = text.prefix { $0.isNumber || $0 == "." || $0 == "-" }
        return Double(digits).map { CGFloat($0) }
    }
}
#endif

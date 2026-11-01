/// The user-facing rendering settings. Preview and Copy as Rich Text use the
/// same options, so the Preview shows the structure that will paste.
public struct RenderOptions: Sendable, Equatable {
    /// Heading Demotion: every heading moves down one level; `h6` stays `h6`.
    public var demotesHeadings: Bool
    /// Draws a single 1px solid table grid with cell padding.
    public var bordersTables: Bool
    /// Renders every newline inside a paragraph as `<br>`, not CommonMark's space.
    public var newlinesAsBreaks: Bool

    public init(demotesHeadings: Bool, bordersTables: Bool, newlinesAsBreaks: Bool) {
        self.demotesHeadings = demotesHeadings
        self.bordersTables = bordersTables
        self.newlinesAsBreaks = newlinesAsBreaks
    }

    /// The out-of-the-box settings.
    public static let `default` = RenderOptions(demotesHeadings: true, bordersTables: true, newlinesAsBreaks: true)
    /// Every option off: plain GFM structure.
    public static let plain = RenderOptions(demotesHeadings: false, bordersTables: false, newlinesAsBreaks: false)
}

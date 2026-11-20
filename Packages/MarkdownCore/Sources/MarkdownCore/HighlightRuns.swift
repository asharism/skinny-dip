import Foundation

/// The styling a stretch of Markdown Source ends up with once every span is
/// applied: the last covering span's color (nil = the plain foreground), bold
/// from any heading or strong span, italic from any emphasis span.
public struct HighlightRun: Equatable, Sendable {
    public var range: NSRange
    public var color: HighlightRole?
    public var bold: Bool
    public var italic: Bool

    public init(range: NSRange, color: HighlightRole? = nil, bold: Bool = false, italic: Bool = false) {
        self.range = range
        self.color = color
        self.bold = bold
        self.italic = italic
    }
}

/// Flattens `spans` (applied in order, so later spans win the color) into
/// adjacent, non-overlapping runs covering `0..<length`. The editor compares
/// these with its text storage and sets attributes only where they differ:
/// in TextKit 2 an attribute change throws away layout for its range, and
/// recoloring the whole document blanks the editor in long files.
/// Spans that run past `length` are dropped. Pure; runs off the main thread.
public func highlightRuns(for spans: [HighlightSpan], length: Int) -> [HighlightRun] {
    guard length > 0 else { return [] }
    let roles = HighlightRole.allCases
    // Per UTF-16 unit: color as 1 + role index (0 = plain); traits as bold 1, italic 2.
    var colors = [UInt8](repeating: 0, count: length)
    var traits = [UInt8](repeating: 0, count: length)
    for span in spans where span.range.location >= 0 && NSMaxRange(span.range) <= length {
        let color = UInt8(roles.firstIndex(of: span.role)! + 1)
        let trait: UInt8 = switch span.role {
        case .heading, .strong: 1
        case .emphasis: 2
        default: 0
        }
        for index in span.range.location ..< NSMaxRange(span.range) {
            colors[index] = color
            traits[index] |= trait
        }
    }
    var runs: [HighlightRun] = []
    var start = 0
    for index in 1 ... length where index == length || colors[index] != colors[start] || traits[index] != traits[start] {
        runs.append(HighlightRun(
            range: NSRange(location: start, length: index - start),
            color: colors[start] == 0 ? nil : roles[Int(colors[start]) - 1],
            bold: traits[start] & 1 != 0,
            italic: traits[start] & 2 != 0
        ))
        start = index
    }
    return runs
}

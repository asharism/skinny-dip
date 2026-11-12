import Foundation
import Markdown

/// What a highlighted run of Markdown Source is, for the native Editor Backend
/// (ADR-0010). Each role maps to a `ResolvedTheme` color; `strong` uses `emphasis`.
public enum HighlightRole: String, Sendable, CaseIterable {
    case heading, marker, emphasis, strong, link, code, quote
}

/// A run of the Markdown Source to color. `range` is in UTF-16 units, so it
/// indexes an `NSString` or `NSTextStorage` directly.
public struct HighlightSpan: Equatable, Sendable {
    public var range: NSRange
    public var role: HighlightRole

    public init(range: NSRange, role: HighlightRole) {
        self.range = range
        self.role = role
    }
}

/// Spans for coloring `source`, built from swift-markdown's source ranges, not
/// a regex grammar. Parents come before their children and a node's markers
/// right after the node, so applying the spans in order lets inner runs win.
/// Pure and thread-safe: the editor calls it off the main thread.
public func highlightSpans(in source: String) -> [HighlightSpan] {
    guard !source.isEmpty else { return [] }
    let document = Document(parsing: source, options: .disableSmartOpts)
    var walker = HighlightWalker(map: SourceMap(source))
    walker.visit(document)
    return walker.spans
}

/// Converts swift-markdown's 1-based (line, UTF-8 column) locations to UTF-8
/// offsets, and UTF-8 offsets to UTF-16 offsets.
private struct SourceMap {
    let bytes: [UInt8]
    /// UTF-8 offset where each line starts. Lines end at `\n`, `\r\n` or `\r`, as in cmark.
    let lineStarts: [Int]
    /// UTF-16 offset for every UTF-8 offset that starts a scalar (and the end).
    private let utf16: [Int32]

    init(_ source: String) {
        bytes = Array(source.utf8)
        var starts = [0]
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x0A {
                starts.append(index + 1)
            } else if byte == 0x0D {
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A { index += 1 }
                starts.append(index + 1)
            }
            index += 1
        }
        lineStarts = starts
        var table = [Int32](repeating: 0, count: bytes.count + 1)
        var units: Int32 = 0
        for (offset, byte) in bytes.enumerated() {
            table[offset] = units
            if byte & 0xC0 != 0x80 { units += byte >= 0xF0 ? 2 : 1 }
        }
        table[bytes.count] = units
        utf16 = table
    }

    var count: Int { bytes.count }

    func offset(_ location: SourceLocation) -> Int {
        let line = min(max(location.line - 1, 0), lineStarts.count - 1)
        return min(max(lineStarts[line] + location.column - 1, 0), bytes.count)
    }

    /// The end of the content of the line holding `offset`, before its line break.
    func lineEnd(from offset: Int) -> Int {
        var index = offset
        while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D { index += 1 }
        return index
    }

    func lineStart(of offset: Int) -> Int {
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return lineStarts[low]
    }

    func skipSpaces(from offset: Int, limit: Int) -> Int {
        var index = offset
        while index < limit, bytes[index] == 0x20 || bytes[index] == 0x09 { index += 1 }
        return index
    }

    func run(of byte: UInt8, from offset: Int, limit: Int) -> Int {
        var index = offset
        while index < limit, bytes[index] == byte { index += 1 }
        return index - offset
    }

    func byte(at offset: Int) -> UInt8? {
        offset >= 0 && offset < bytes.count ? bytes[offset] : nil
    }

    func nsRange(_ lower: Int, _ upper: Int) -> NSRange? {
        let lower = min(max(lower, 0), bytes.count)
        let upper = min(max(upper, lower), bytes.count)
        guard upper > lower else { return nil }
        let start = Int(utf16[lower])
        return NSRange(location: start, length: Int(utf16[upper]) - start)
    }
}

private struct HighlightWalker: MarkupWalker {
    let map: SourceMap
    var spans: [HighlightSpan] = []

    init(map: SourceMap) {
        self.map = map
    }

    private mutating func add(_ lower: Int, _ upper: Int, _ role: HighlightRole) {
        guard let range = map.nsRange(lower, upper) else { return }
        spans.append(HighlightSpan(range: range, role: role))
    }

    private func bounds(_ markup: Markup) -> (Int, Int)? {
        guard let range = markup.range else { return nil }
        let lower = map.offset(range.lowerBound)
        let upper = map.offset(range.upperBound)
        return upper > lower ? (lower, upper) : nil
    }

    mutating func visitHeading(_ heading: Heading) {
        guard let (lower, upper) = bounds(heading) else { return descendInto(heading) }
        add(lower, upper, .heading)
        let first = map.skipSpaces(from: lower, limit: upper)
        let hashes = map.run(of: UInt8(ascii: "#"), from: first, limit: upper)
        if hashes > 0 {
            add(first, first + hashes, .marker)
        } else {
            // Setext: the `===` or `---` underline on the last line.
            let lineStart = map.lineStart(of: max(lower, upper - 1))
            let start = map.skipSpaces(from: lineStart, limit: upper)
            add(start, min(map.lineEnd(from: start), upper), .marker)
        }
        descendInto(heading)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        delimited(emphasis, role: .emphasis, width: 1)
    }

    mutating func visitStrong(_ strong: Strong) {
        delimited(strong, role: .strong, width: 2)
    }

    private mutating func delimited(_ markup: Markup, role: HighlightRole, width: Int) {
        guard let (lower, upper) = bounds(markup) else { return descendInto(markup) }
        add(lower, upper, role)
        if upper - lower >= width * 2 {
            add(lower, lower + width, .marker)
            add(upper - width, upper, .marker)
        }
        descendInto(markup)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let (lower, upper) = bounds(inlineCode) else { return }
        add(lower, upper, .code)
        let ticks = map.run(of: UInt8(ascii: "`"), from: lower, limit: upper)
        if ticks > 0, upper - lower >= ticks * 2 {
            add(lower, lower + ticks, .marker)
            add(upper - ticks, upper, .marker)
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        guard var (lower, upper) = bounds(codeBlock) else { return }
        // Some ranges end past the closing line break; keep the span on the text.
        while upper > lower, let last = map.byte(at: upper - 1), last == 0x0A || last == 0x0D { upper -= 1 }
        add(lower, upper, .code)
        let first = map.skipSpaces(from: lower, limit: upper)
        guard let fence = map.byte(at: first), fence == UInt8(ascii: "`") || fence == UInt8(ascii: "~") else { return }
        let width = map.run(of: fence, from: first, limit: upper)
        let openEnd = min(map.lineEnd(from: first), upper)
        add(first, openEnd, .marker)
        let closeLine = map.lineStart(of: upper - 1)
        guard closeLine > openEnd else { return }
        let closeStart = map.skipSpaces(from: closeLine, limit: upper)
        if map.run(of: fence, from: closeStart, limit: upper) >= width {
            add(closeStart, upper, .marker)
        }
    }

    mutating func visitLink(_ link: Link) {
        linked(link, opener: 1)
    }

    mutating func visitImage(_ image: Image) {
        linked(image, opener: 2)
    }

    /// `[text](url)`: the whole run is a link; `[` and `](url)` are markers.
    private mutating func linked(_ markup: Markup, opener: Int) {
        guard let (lower, upper) = bounds(markup) else { return descendInto(markup) }
        add(lower, upper, .link)
        let open = map.byte(at: lower)
        let bracketed = open == UInt8(ascii: "[") || open == UInt8(ascii: "<")
            || (opener == 2 && open == UInt8(ascii: "!"))
        if bracketed {
            let textEnd = markup.children.compactMap(\.range).last.map { map.offset($0.upperBound) }
            add(lower, lower + opener, .marker)
            add(textEnd ?? lower + opener, upper, .marker)
        }
        descendInto(markup)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        guard let range = blockQuote.range, let (lower, upper) = bounds(blockQuote) else {
            return descendInto(blockQuote)
        }
        add(lower, upper, .quote)
        let column = range.lowerBound.column - 1
        for line in range.lowerBound.line...range.upperBound.line where line - 1 < map.lineStarts.count {
            let lineStart = map.lineStarts[line - 1]
            let lineEnd = map.lineEnd(from: lineStart)
            let from = min(lineStart + column, lineEnd)
            let start = map.skipSpaces(from: from, limit: lineEnd)
            if map.byte(at: start) == UInt8(ascii: ">"), start < upper {
                add(start, start + 1, .marker)
            }
        }
        descendInto(blockQuote)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        guard let (lower, upper) = bounds(listItem) else { return descendInto(listItem) }
        let start = map.skipSpaces(from: lower, limit: upper)
        var end = start
        if let byte = map.byte(at: start), byte == UInt8(ascii: "-") || byte == UInt8(ascii: "*") || byte == UInt8(ascii: "+") {
            end = start + 1
        } else {
            while let byte = map.byte(at: end), end < upper, byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") { end += 1 }
            if let byte = map.byte(at: end), end > start, byte == UInt8(ascii: ".") || byte == UInt8(ascii: ")") {
                end += 1
            } else {
                end = start
            }
        }
        add(start, end, .marker)
        if listItem.checkbox != nil {
            let box = map.skipSpaces(from: end, limit: upper)
            if map.byte(at: box) == UInt8(ascii: "["), map.byte(at: box + 2) == UInt8(ascii: "]") {
                add(box, box + 3, .marker)
            }
        }
        descendInto(listItem)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        guard let (lower, upper) = bounds(thematicBreak) else { return }
        add(lower, min(map.lineEnd(from: lower), upper), .marker)
    }
}

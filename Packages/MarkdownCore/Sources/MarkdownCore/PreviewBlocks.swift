import Markdown

/// The source lines of each top-level block, so the Preview can highlight the block
/// the Editor's caret is in. A block is named by its first line, which is the
/// `data-source-line` anchor `PreviewHTML` puts on it (ADR-0006).
public struct PreviewBlocks: Equatable, Sendable {
    /// 1-based, inclusive line spans of the top-level blocks, in document order.
    public let ranges: [ClosedRange<Int>]

    public static let empty = PreviewBlocks(ranges: [])

    public init(source: String) {
        let blocks = Document(parsing: source, options: .disableSmartOpts).children.compactMap(\.range)
        ranges = blocks.map { range in
            let first = range.lowerBound.line
            var last = range.upperBound.line
            // A block whose range ends at column 1 of the next line ends on the line before.
            if range.upperBound.column == 1, last > first { last -= 1 }
            return first...max(first, last)
        }
    }

    init(ranges: [ClosedRange<Int>]) {
        self.ranges = ranges
    }

    /// The first line of the top-level block containing `line` (1-based), or nil on a
    /// blank line between blocks.
    public func blockLine(containing line: Int) -> Int? {
        var low = 0, high = ranges.count - 1
        while low <= high {
            let mid = (low + high) / 2
            if ranges[mid].upperBound < line { low = mid + 1 }
            else if ranges[mid].lowerBound > line { high = mid - 1 }
            else { return ranges[mid].lowerBound }
        }
        return nil
    }
}

/// One Preview render: the HTML and the block lines of the source it came from, so
/// the highlight always names an anchor that is on the page.
public struct PreviewRender: Equatable, Sendable {
    public let html: String
    public let blocks: PreviewBlocks

    public init(html: String, blocks: PreviewBlocks) {
        self.html = html
        self.blocks = blocks
    }

    public static let empty = PreviewRender(html: "", blocks: .empty)
}

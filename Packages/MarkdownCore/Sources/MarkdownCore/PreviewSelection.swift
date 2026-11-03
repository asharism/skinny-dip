import Markdown

/// Maps a selection in the Preview back to the Markdown Source, so copying it takes
/// the same path as an editor selection (Bare HTML, never WebKit's styled copy).
///
/// The Preview only knows the `data-source-line` of each top-level block (ADR-0006),
/// so the mapping is block by block: a selection that touches part of a paragraph
/// copies the whole paragraph.
public enum PreviewSelection {
    /// The Markdown Source of the top-level blocks starting at `firstBlockLine` through
    /// the one starting at `lastBlockLine` (1-based), or nil when either line starts
    /// no top-level block, for example after the document changed under the Preview.
    public static func range(in source: String, firstBlockLine: Int, lastBlockLine: Int) -> Range<String.Index>? {
        let low = min(firstBlockLine, lastBlockLine), high = max(firstBlockLine, lastBlockLine)
        let blocks = Document(parsing: source, options: .disableSmartOpts).children.compactMap(\.range)
        guard let first = blocks.first(where: { $0.lowerBound.line == low }),
              let last = blocks.first(where: { $0.lowerBound.line == high })
        else { return nil }
        let lines = lineStarts(in: source)
        guard let start = index(line: first.lowerBound.line, in: lines),
              let endLine = index(line: last.upperBound.line, in: lines)
        else { return nil }
        // The last block ends on `upperBound.line`; take that whole line, minus its break.
        var end = source[endLine...].firstIndex(where: \.isNewline) ?? source.endIndex
        // A block whose range ends at column 1 of the next line ends on the line before.
        if last.upperBound.column == 1, last.upperBound.line > first.lowerBound.line,
           let previous = index(line: last.upperBound.line - 1, in: lines) {
            end = source[previous...].firstIndex(where: \.isNewline) ?? source.endIndex
        }
        guard start <= end else { return nil }
        return start..<end
    }

    private static func lineStarts(in source: String) -> [String.Index] {
        var starts = [source.startIndex]
        var index = source.startIndex
        while index < source.endIndex {
            let next = source.index(after: index)
            // "\r\n" is one Character in Swift, so this counts each line break once.
            if source[index].isNewline { starts.append(next) }
            index = next
        }
        return starts
    }

    private static func index(line: Int, in starts: [String.Index]) -> String.Index? {
        starts.indices.contains(line - 1) ? starts[line - 1] : nil
    }
}

import Foundation

/// How a logical line ends. Lines break at `\n`, `\r\n` or `\r`, the same as
/// `LineNumbering`; the last line has no terminator.
public enum LineTerminator: String, Equatable, Sendable {
    case none = ""
    case lf = "\n"
    case crlf = "\r\n"
    case cr = "\r"

    public var length: Int { rawValue.utf16.count }
}

/// One logical line in UTF-16 offsets.
public struct LineRange: Equatable, Sendable {
    /// The line's text, without its terminator.
    public var content: Range<Int>
    public var terminator: LineTerminator

    public init(content: Range<Int>, terminator: LineTerminator) {
        self.content = content
        self.terminator = terminator
    }

    public var start: Int { content.lowerBound }
    /// The content plus the terminator.
    public var full: Range<Int> { content.lowerBound..<(content.upperBound + terminator.length) }

    /// The line's content as a substring of `text`, for `MarkdownEditing.linePrefix`.
    public func text(in text: String) -> Substring {
        let utf16 = text.utf16
        let lower = utf16.index(utf16.startIndex, offsetBy: content.lowerBound)
        let upper = utf16.index(lower, offsetBy: content.count)
        return text[lower..<upper]
    }
}

extension MarkdownEditing {
    /// The logical line holding UTF-16 `offset`, clamped to the text. An offset
    /// at the end of a line's content, or inside its `\r\n`, belongs to that line.
    public static func lineRange(containing offset: Int, in text: String) -> LineRange {
        lineRange(containing: offset, units: Array(text.utf16))
    }

    /// The lines a selection touches, in order. A non-empty selection ending at
    /// column 0 of a line doesn't touch that line; a caret touches its own line.
    public static func lineRanges(touching selection: Range<Int>, in text: String) -> [LineRange] {
        let units = Array(text.utf16)
        var lines = [lineRange(containing: selection.lowerBound, units: units)]
        let end = min(selection.upperBound, units.count)
        // Ending at column 0 of a later line: that line isn't touched.
        let touchesEndLine = selection.isEmpty || lineRange(containing: end, units: units).start != end
        while let current = lines.last, current.terminator != .none {
            let next = current.full.upperBound
            guard next < end || (next == end && touchesEndLine) else { break }
            lines.append(lineRange(containing: next, units: units))
        }
        return lines
    }

    /// The line break an Editing Command inserts near `offset`: the line's own
    /// terminator, else the line above's (the last line has none), else `\n`.
    public static func lineEnding(near offset: Int, in text: String) -> String {
        let line = lineRange(containing: offset, in: text)
        if line.terminator != .none { return line.terminator.rawValue }
        guard line.start > 0 else { return "\n" }
        let above = lineRange(containing: line.start - 1, in: text)
        return above.terminator == .none ? "\n" : above.terminator.rawValue
    }

    private static func lineRange(containing offset: Int, units: [UInt16]) -> LineRange {
        var offset = min(max(offset, 0), units.count)
        // Between the `\r` and `\n` of a `\r\n`: still the line before.
        if offset > 0, offset < units.count, units[offset - 1] == 0x0D, units[offset] == 0x0A { offset -= 1 }
        var start = offset
        while start > 0, !isBreak(units[start - 1]) { start -= 1 }
        var end = offset
        while end < units.count, !isBreak(units[end]) { end += 1 }
        return LineRange(content: start..<end, terminator: terminator(at: end, in: units))
    }

    static func isBreak(_ unit: UInt16) -> Bool { unit == 0x0A || unit == 0x0D }

    private static func terminator(at end: Int, in units: [UInt16]) -> LineTerminator {
        guard end < units.count else { return .none }
        if units[end] == 0x0A { return .lf }
        if end + 1 < units.count, units[end + 1] == 0x0A { return .crlf }
        return .cr
    }
}

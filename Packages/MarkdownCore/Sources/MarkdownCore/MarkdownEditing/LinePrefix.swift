/// A list marker at the start of a line: `-`, `*`, `+`, or `N.` / `N)`.
public struct ListMarker: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case bullet(Character)
        case ordered(number: Int, delimiter: Character)
    }

    public var kind: Kind
    /// The marker's own characters (`-`, `10)`), UTF-16 offsets in the line.
    public var range: Range<Int>

    public init(kind: Kind, range: Range<Int>) {
        self.kind = kind
        self.range = range
    }

    public var isOrdered: Bool {
        if case .ordered = kind { return true }
        return false
    }

    /// The item's number, for an ordered marker.
    public var number: Int? {
        if case .ordered(let number, _) = kind { return number }
        return nil
    }

    /// The bullet character, or the ordered marker's `.` / `)`.
    public var delimiter: Character {
        switch kind {
        case .bullet(let bullet): bullet
        case .ordered(_, let delimiter): delimiter
        }
    }
}

/// A task box after a list marker: `[ ]`, `[x]` or `[X]`.
public struct TaskBox: Equatable, Sendable {
    public var isChecked: Bool
    /// The three characters `[ ]`, UTF-16 offsets in the line.
    public var range: Range<Int>

    public init(isChecked: Bool, range: Range<Int>) {
        self.isChecked = isChecked
        self.range = range
    }
}

/// The leading Markdown syntax of one line, in UTF-16 offsets from the start
/// of the line: indent, then blockquote markers, then a list marker and task
/// box, then the user's text at `contentStart`.
public struct LinePrefix: Equatable, Sendable {
    /// Columns of leading whitespace; a tab advances to the next multiple of 4.
    public var indent: Int
    /// UTF-16 length of that leading whitespace.
    public var indentLength: Int
    /// How many `>` markers (`> > a` is 2).
    public var quoteDepth: Int
    /// Where the indent and blockquote markers (with the space after the last
    /// `>`) end. Equals `indentLength` with no blockquote.
    public var quoteEnd: Int
    public var list: ListMarker?
    /// Only after a list marker, and only with a space after `]`.
    public var task: TaskBox?
    /// Where the user's text begins: after the marker, the task box and the
    /// whitespace after them. The line's length for an empty item (`- `).
    public var contentStart: Int

    public init(
        indent: Int = 0,
        indentLength: Int = 0,
        quoteDepth: Int = 0,
        quoteEnd: Int = 0,
        list: ListMarker? = nil,
        task: TaskBox? = nil,
        contentStart: Int = 0
    ) {
        self.indent = indent
        self.indentLength = indentLength
        self.quoteDepth = quoteDepth
        self.quoteEnd = quoteEnd
        self.list = list
        self.task = task
        self.contentStart = contentStart
    }

    /// True when the line starts with a blockquote or list marker.
    public var hasMarker: Bool { quoteDepth > 0 || list != nil }
}

extension MarkdownEditing {
    /// Parses the leading syntax of `line`, one logical line without its
    /// terminator (`LineRange.text(in:)`). A simple scan, not CommonMark's
    /// full rules: any indent may start a list item, so nested items count.
    public static func linePrefix(_ line: Substring) -> LinePrefix {
        let units = Array(line.utf16.prefix { !isBreak($0) })
        var prefix = LinePrefix()
        var i = 0

        func isSpace(_ index: Int) -> Bool { index < units.count && (units[index] == 0x20 || units[index] == 0x09) }
        func skipSpaces() { while isSpace(i) { i += 1 } }

        // Indent.
        while isSpace(i) {
            prefix.indent = units[i] == 0x09 ? (prefix.indent / 4 + 1) * 4 : prefix.indent + 1
            i += 1
        }
        prefix.indentLength = i

        // Blockquote markers: `>`, optionally followed by a space, repeated.
        var quoteEnd = i
        while i < units.count, units[i] == 0x3E {
            prefix.quoteDepth += 1
            i += 1
            if isSpace(i) { i += 1 }
            quoteEnd = i
            let save = i
            skipSpaces()
            if i >= units.count || units[i] != 0x3E { i = save; break }
        }
        prefix.quoteEnd = quoteEnd

        // List marker, after any spaces inside the quote.
        let markerSearch = i
        skipSpaces()
        let markerStart = i
        var kind: ListMarker.Kind?
        if i < units.count, units[i] == 0x2D || units[i] == 0x2A || units[i] == 0x2B {
            kind = .bullet(Character(UnicodeScalar(units[i])!))
            i += 1
        } else {
            var number = 0
            var digits = 0
            while i < units.count, (0x30...0x39).contains(units[i]), digits < 9 {
                number = number * 10 + Int(units[i] - 0x30)
                digits += 1
                i += 1
            }
            if digits > 0, i < units.count, units[i] == 0x2E || units[i] == 0x29 {
                kind = .ordered(number: number, delimiter: Character(UnicodeScalar(units[i])!))
                i += 1
            }
        }
        // A marker needs whitespace or the line's end after it: `-a` and `#tag` aren't lists.
        guard let kind, i == units.count || isSpace(i) else {
            i = markerSearch
            skipSpaces()
            prefix.contentStart = i
            return prefix
        }
        prefix.list = ListMarker(kind: kind, range: markerStart..<i)
        skipSpaces()

        // Task box: `[ ]`, `[x]`, `[X]`, then a space.
        if i + 3 < units.count, units[i] == 0x5B, units[i + 2] == 0x5D, isSpace(i + 3) {
            switch units[i + 1] {
            case 0x20: prefix.task = TaskBox(isChecked: false, range: i..<(i + 3))
            case 0x78, 0x58: prefix.task = TaskBox(isChecked: true, range: i..<(i + 3))
            default: break
            }
            if prefix.task != nil {
                i += 3
                skipSpaces()
            }
        }
        prefix.contentStart = i
        return prefix
    }
}

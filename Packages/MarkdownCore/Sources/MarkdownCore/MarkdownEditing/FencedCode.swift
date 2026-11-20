extension MarkdownEditing {
    /// True when the line holding UTF-16 `line` (any offset on it, such as the
    /// caret) is inside a fenced code block: a fence opened above it and not yet
    /// closed. The closing fence line counts as inside; the opening one doesn't.
    /// A simple line scan: a fence is 3+ backticks or tildes after any indent,
    /// and only a fence of the same character, at least as long, with nothing
    /// after it closes it. An unclosed fence runs to the end of the document.
    public static func isInsideFencedCode(line: Int, in text: String) -> Bool {
        let target = lineRange(containing: line, in: text).start
        var open: (character: UInt16, length: Int)?
        var offset = 0
        for rawLine in text.utf16.split(omittingEmptySubsequences: false, whereSeparator: { $0 == 0x0A }) {
            if offset >= target { break }
            var units = Array(rawLine)
            if units.last == 0x0D { units.removeLast() }
            if let fence = fence(in: units) {
                if let current = open {
                    if fence.character == current.character, fence.length >= current.length, fence.isBare { open = nil }
                } else if fence.character == 0x7E || !fence.hasBacktickInInfo {
                    open = (fence.character, fence.length)
                }
            }
            offset += rawLine.count + 1
        }
        return open != nil
    }

    private static func fence(in units: [UInt16]) -> (character: UInt16, length: Int, isBare: Bool, hasBacktickInInfo: Bool)? {
        var i = 0
        while i < units.count, units[i] == 0x20 || units[i] == 0x09 { i += 1 }
        guard i < units.count, units[i] == 0x60 || units[i] == 0x7E else { return nil }
        let character = units[i]
        let start = i
        while i < units.count, units[i] == character { i += 1 }
        let length = i - start
        guard length >= 3 else { return nil }
        let info = units[i...]
        return (character, length, info.allSatisfy { $0 == 0x20 || $0 == 0x09 }, info.contains(0x60))
    }
}

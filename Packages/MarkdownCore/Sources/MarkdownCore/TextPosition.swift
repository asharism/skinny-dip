import Foundation

/// 1-based line and column for the Editor footer. The column counts `Character`s,
/// not UTF-16 code units. `utf16Offset` is the cursor the editor reports.
public enum TextPosition {
    public static func lineColumn(in text: String, utf16Offset: Int) -> (line: Int, column: Int) {
        let clamped = min(max(utf16Offset, 0), text.utf16.count)
        let index = index(in: text, utf16Offset: clamped)
        var line = 1
        var column = 1
        var cursor = text.startIndex
        while cursor < index {
            if text[cursor] == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            cursor = text.index(after: cursor)
        }
        return (line, column)
    }

    private static func index(in text: String, utf16Offset: Int) -> String.Index {
        guard utf16Offset > 0 else { return text.startIndex }
        if let range = UTF16Selection.range(in: text, from: 0, to: utf16Offset) {
            return range.upperBound
        }
        return text.endIndex
    }
}

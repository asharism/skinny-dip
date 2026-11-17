import Foundation

/// Logical lines of the Markdown Source in UTF-16 offsets, the units `NSTextView`
/// and CodeMirror report. A line ends at `\n`, `\r\n` or `\r`; a trailing break
/// adds an empty last line, and an empty document has one line. The native
/// editor's line-number gutter and scroll sync both count lines this way.
public struct LineNumbering: Equatable, Sendable {
    /// Where each line starts. Never empty: the first line starts at 0.
    public let starts: [Int]

    public init(_ text: String) {
        var starts = [0]
        var offset = 0
        var previousCR = false
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A {
                if previousCR { starts[starts.count - 1] = offset } else { starts.append(offset) }
            } else if unit == 0x0D {
                starts.append(offset)
            }
            previousCR = unit == 0x0D
        }
        self.starts = starts
    }

    public var count: Int { starts.count }

    /// The 1-based line holding `offset`, clamped to the document.
    public func line(atUTF16 offset: Int) -> Int {
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    /// Where 1-based `line` starts, clamped to the document.
    public func start(ofLine line: Int) -> Int {
        starts[min(max(line - 1, 0), starts.count - 1)]
    }

    /// How many digits the gutter reserves: the widest number, at least two,
    /// so the text only moves when the document passes 99, 999 and so on.
    public static func digits(forLineCount count: Int) -> Int {
        max(2, String(max(count, 1)).count)
    }
}

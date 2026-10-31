/// Maps UTF-16 code-unit offsets from the CodeMirror bridge into Swift `String.Index` ranges.
public enum UTF16Selection {
    /// Converts `from`..`to` UTF-16 offsets (inclusive start, exclusive end) into a range in `string`.
    public static func range(in string: String, from: Int, to: Int) -> Range<String.Index>? {
        guard from >= 0, to >= from else { return nil }
        let view = string.utf16
        guard from <= view.count, to <= view.count else { return nil }
        guard let fromUTF16 = view.index(view.startIndex, offsetBy: from, limitedBy: view.endIndex),
              let toUTF16 = view.index(view.startIndex, offsetBy: to, limitedBy: view.endIndex)
        else { return nil }
        guard let lower = String.Index(fromUTF16, within: string),
              let upper = String.Index(toUTF16, within: string)
        else { return nil }
        return lower..<upper
    }
}

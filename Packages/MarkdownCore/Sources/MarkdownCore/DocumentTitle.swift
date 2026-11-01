import Foundation

/// Suggested Tab titles for documents that have never been saved (spec §2).
public enum DocumentTitle {
    public static let untitled = "Untitled"

    public static func suggested(from source: String) -> String {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let line = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            return untitled
        }
        var text = stripBlockMarkers(String(line))
        text = stripInline(text)
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        text = truncate(text, limit: 40)
        return text.isEmpty ? untitled : text
    }

    /// "<base> copy". A saved file uses its name without the extension; a scratch
    /// uses the current suggested title. An empty document is "Untitled copy".
    public static func duplicateTitle(fileName: String?, suggested: String) -> String {
        let base: String
        if let fileName {
            let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
            base = stem.isEmpty ? untitled : stem
        } else if suggested.isEmpty || suggested == untitled {
            base = untitled
        } else {
            base = suggested
        }
        return "\(base) copy"
    }

    private static func stripBlockMarkers(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            if let range = text.prefixMatch(of: /^#{1,6}(?:\s+|$)/)?.range, !range.isEmpty {
                text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                changed = true
                continue
            }
            if text.hasPrefix(">") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
                changed = true
                continue
            }
            if let range = text.prefixMatch(of: /^[-*+](?:\s+|$)/)?.range {
                text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                changed = true
                continue
            }
            if let range = text.prefixMatch(of: /^\d+[.)](?:\s+|$)/)?.range {
                text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                changed = true
                continue
            }
            if text.hasPrefix("[ ]") || text.hasPrefix("[x]") || text.hasPrefix("[X]") {
                text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return text
    }

    private static func stripInline(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        result = result.replacingOccurrences(of: "~~", with: "")
        result = result.replacingOccurrences(of: "`", with: "")
        result = result.replacingOccurrences(of: "*", with: "")
        result = result.replacingOccurrences(of: "_", with: "")
        return result
    }

    private static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        let head = text[..<end]
        guard let space = head.lastIndex(of: " "), space > text.startIndex else {
            return String(head) + "…"
        }
        return text[..<space].trimmingCharacters(in: .whitespaces) + "…"
    }
}

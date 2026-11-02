import Foundation

/// Words for the Editor footer. A word is a whitespace-separated run that
/// contains a letter or a digit. Markdown markers alone do not count, and a
/// task box (`[x]`, `[ ]`) is a marker even though it contains a letter.
public enum WordCount {
    public static func count(in source: String) -> Int {
        source.split(whereSeparator: \.isWhitespace).reduce(into: 0) { total, token in
            if counts(token) { total += 1 }
        }
    }

    private static func counts(_ token: Substring) -> Bool {
        if token.wholeMatch(of: /^\[[ xX]\]$/) != nil { return false }
        return token.contains { $0.isLetter || $0.isNumber }
    }
}

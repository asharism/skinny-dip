import Testing
@testable import MarkdownCore

struct WordCountTests {
    @Test func countsWords() {
        let cases = [
            ("", 0),
            ("# Hello world", 2),
            ("- [x] done", 1),
            ("| a | b |", 2),
            ("don't stop", 2),
            ("日本語 テキスト", 2),
            ("--- *** ___", 0),
        ]
        for (source, expected) in cases {
            #expect(WordCount.count(in: source) == expected)
        }
    }
}

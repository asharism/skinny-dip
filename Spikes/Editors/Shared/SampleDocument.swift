import Foundation

/// The same 10,000-line Markdown document in every editor spike, so results compare.
/// The top section is a scripted test bench for the scorecard; the rest is bulk.
enum SampleDocument {
    static let lineCount = 10_000

    static let testBench = """
    # Editor spike test bench

    Spell check and autocorrect: teh quick brwon fox recieve definately.
    Dictation: put the caret on the next line and dictate a sentence.

    Writing Tools: select this paragraph and choose Rewrite or Proofread. Their going to the store tomorow, and they has many thing to buy for the party.

    Multi-cursor ⌘D: put the caret on fox and press ⌘D repeatedly.
    The fox jumps. The fox sleeps. The fox eats. The fox runs.

    Add cursor above/below (⌃⇧↑ / ⌃⇧↓) and ⌘-click: type on all of these at once.
    - alpha
    - beta
    - gamma
    - delta

    ---

    """

    static let text: String = {
        var lines = testBench.components(separatedBy: "\n")
        var section = 1
        while lines.count < lineCount {
            lines += [
                "## Section \(section)",
                "",
                "A paragraph with **bold**, *italic*, `code` and a [link](https://example.com/\(section)). It runs long enough to soft-wrap in a normal window width so wrapping cost is part of the test.",
                "",
                "- item one",
                "- item two with `inline code`",
                "  - nested item",
                "- [ ] task \(section)",
                "",
                "| Column A | Column B |",
                "| --- | --- |",
                "| \(section) | value |",
                "",
                "```swift",
                "let section = \(section)",
                "print(\"section \\(section)\")",
                "```",
                "",
            ]
            section += 1
        }
        return lines.prefix(lineCount).joined(separator: "\n")
    }()
}

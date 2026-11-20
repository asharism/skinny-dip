import Foundation
import Testing
@testable import MarkdownCore

/// `highlightRuns` flattens overlapping spans into the styling each character
/// ends up with, so the editor can compare against the text storage and touch
/// only what changed (a whole-document attribute pass throws away TextKit 2's
/// layout and blanks the editor in long files).
struct HighlightRunsTests {
    private func span(_ location: Int, _ length: Int, _ role: HighlightRole) -> HighlightSpan {
        HighlightSpan(range: NSRange(location: location, length: length), role: role)
    }

    @Test func noSpansIsOnePlainRun() {
        #expect(highlightRuns(for: [], length: 5) == [HighlightRun(range: NSRange(location: 0, length: 5))])
    }

    @Test func emptyTextHasNoRuns() {
        #expect(highlightRuns(for: [], length: 0).isEmpty)
    }

    @Test func laterSpansWinTheColor() {
        // A heading "## Hi" with its "##" marker.
        let runs = highlightRuns(for: [span(0, 5, .heading), span(0, 2, .marker)], length: 6)
        #expect(runs == [
            HighlightRun(range: NSRange(location: 0, length: 2), color: .marker, bold: true),
            HighlightRun(range: NSRange(location: 2, length: 3), color: .heading, bold: true),
            HighlightRun(range: NSRange(location: 5, length: 1)),
        ])
    }

    @Test func traitsAccumulateAcrossNestedSpans() {
        // "***bi***": strong around emphasis.
        let runs = highlightRuns(for: [span(0, 8, .strong), span(1, 6, .emphasis)], length: 8)
        #expect(runs == [
            HighlightRun(range: NSRange(location: 0, length: 1), color: .strong, bold: true),
            HighlightRun(range: NSRange(location: 1, length: 6), color: .emphasis, bold: true, italic: true),
            HighlightRun(range: NSRange(location: 7, length: 1), color: .strong, bold: true),
        ])
    }

    @Test func spansPastTheEndAreDropped() {
        let runs = highlightRuns(for: [span(2, 10, .code)], length: 4)
        #expect(runs == [HighlightRun(range: NSRange(location: 0, length: 4))])
    }

    @Test func runsCoverTheWholeText() {
        let source = "# Head\n\n**bold** and *it* and `code` [l](u)\n> quote\n"
        let length = (source as NSString).length
        let runs = highlightRuns(for: highlightSpans(in: source), length: length)
        #expect(runs.first?.range.location == 0)
        #expect(runs.map(\.range.length).reduce(0, +) == length)
        for (a, b) in zip(runs, runs.dropFirst()) {
            #expect(NSMaxRange(a.range) == b.range.location)
            #expect(a.color != b.color || a.bold != b.bold || a.italic != b.italic)
        }
    }
}

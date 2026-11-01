import Testing
@testable import MarkdownCore

struct DocumentTitleTests {
    @Test func emptyIsUntitled() {
        #expect(DocumentTitle.suggested(from: "") == "Untitled")
        #expect(DocumentTitle.suggested(from: "\n\n  \n") == "Untitled")
        #expect(DocumentTitle.suggested(from: "#") == "Untitled")
    }

    @Test func usesTheFirstContentLine() {
        #expect(DocumentTitle.suggested(from: "# Weekly status — Payments\n\nHi") == "Weekly status — Payments")
        #expect(DocumentTitle.suggested(from: "\n\n## Shipped") == "Shipped")
    }

    @Test func stripsMarkersAndInlineSyntax() {
        #expect(DocumentTitle.suggested(from: "> quoted *idea*") == "quoted idea")
        #expect(DocumentTitle.suggested(from: "- [x] Outlook paste check") == "Outlook paste check")
        #expect(DocumentTitle.suggested(from: "1. **migration** runs") == "migration runs")
        #expect(DocumentTitle.suggested(from: "See [DEV-412](https://x/y) now") == "See DEV-412 now")
        #expect(DocumentTitle.suggested(from: "`code` and ~~old~~") == "code and old")
    }

    @Test func truncatesAtAWordBoundary() {
        let sentence = "Please truncate this overly long suggested document title no"
        #expect(sentence.count == 60)
        #expect(DocumentTitle.suggested(from: sentence) == "Please truncate this overly long…")
    }

    @Test func duplicateTitles() {
        #expect(DocumentTitle.duplicateTitle(fileName: "notes.md", suggested: "Ignored") == "notes copy")
        #expect(DocumentTitle.duplicateTitle(fileName: nil, suggested: "Weekly status") == "Weekly status copy")
        #expect(DocumentTitle.duplicateTitle(fileName: nil, suggested: "Untitled") == "Untitled copy")
        #expect(DocumentTitle.duplicateTitle(fileName: nil, suggested: "") == "Untitled copy")
    }
}

import Foundation
import Testing
import MarkdownCore

/// Bare HTML from our renderer should convert back to Markdown that re-renders
/// to the same HTML. The options are the clipboard's, minus Heading Demotion
/// (which is one-way by design). Newlines must be `<br>`: in HTML a newline
/// inside text is just a space, so a soft break can't survive the trip.
struct HTMLRoundTripTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        var testDescription: String { "plain/\(name)" }
    }

    static let plainDirectory = Bundle.module.resourceURL!.appending(path: "Golden/plain")

    static var cases: [Case] {
        let path = plainDirectory.path()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return files.filter { $0.hasSuffix(".md") }.sorted()
            .map { String($0.dropLast(3)) }
            // Paste as Markdown drops images (Build Plan, Commands).
            .filter { $0 != "images" }
            .map { Case(name: $0) }
    }

    static let options = RenderOptions(demotesHeadings: false, bordersTables: true, newlinesAsBreaks: true)

    @Test(arguments: cases)
    func bareHTMLRoundTrips(_ golden: Case) throws {
        let source = try String(
            contentsOf: Self.plainDirectory.appending(path: "\(golden.name).md"),
            encoding: .utf8
        )
        let html = BareHTML.render(source, options: Self.options)
        let markdown = HTMLToMarkdown.convert(html)
        let again = BareHTML.render(markdown, options: Self.options)

        #expect(again == html)
    }
}

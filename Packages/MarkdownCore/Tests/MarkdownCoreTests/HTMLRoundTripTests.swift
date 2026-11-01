import Foundation
import Testing
import MarkdownCore

/// Bare HTML from our renderer should convert back to Markdown that re-renders
/// to the same structure (plain options, no heading demotion or `<br>` newlines).
struct HTMLRoundTripTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        var testDescription: String { "plain/\(name)" }
    }

    static let plainDirectory = Bundle.module.resourceURL!.appending(path: "Golden/plain")

    static var cases: [Case] {
        let path = plainDirectory.path()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return files.filter { $0.hasSuffix(".md") }.sorted().map { Case(name: String($0.dropLast(3))) }
    }

    @Test(arguments: cases)
    func bareHTMLRoundTrips(_ golden: Case) throws {
        let source = try String(
            contentsOf: Self.plainDirectory.appending(path: "\(golden.name).md"),
            encoding: .utf8
        )
        let html = BareHTML.render(source, options: .plain)
        let markdown = HTMLToMarkdown.convert(html)
        let again = BareHTML.render(markdown, options: .plain)

        #expect(again == html)
    }
}

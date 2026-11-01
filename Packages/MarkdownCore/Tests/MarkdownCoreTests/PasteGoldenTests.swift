import Foundation
import Testing
import MarkdownCore

/// Each `Golden/paste/<name>.html` is converted to Markdown and compared with
/// `<name>.md`. Add a case by dropping in a new pair of files.
struct PasteGoldenTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        var testDescription: String { "paste/\(name)" }
    }

    static let pasteDirectory = Bundle.module.resourceURL!.appending(path: "Golden/paste")

    static var cases: [Case] {
        let path = pasteDirectory.path()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return files.filter { $0.hasSuffix(".html") }.sorted().map { Case(name: String($0.dropLast(5))) }
    }

    @Test(arguments: cases)
    func convertsPastedHTML(_ golden: Case) throws {
        let folder = Self.pasteDirectory
        let html = try String(contentsOf: folder.appending(path: "\(golden.name).html"), encoding: .utf8)
        let expected = try String(contentsOf: folder.appending(path: "\(golden.name).md"), encoding: .utf8)

        #expect(HTMLToMarkdown.convert(html) == expected.trimmingTrailingNewlines())
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}

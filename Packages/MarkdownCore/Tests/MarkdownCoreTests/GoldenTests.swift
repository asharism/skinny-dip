import Foundation
import Testing
import MarkdownCore

/// Each `Golden/<name>.md` is rendered and compared with `Golden/<name>.html`.
/// Add a case by dropping in a new pair of files.
struct GoldenTests {
    static let goldenDirectory = Bundle.module.resourceURL!.appending(path: "Golden")

    static var caseNames: [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: goldenDirectory.path())) ?? []
        return files.filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.sorted()
    }

    @Test(arguments: caseNames)
    func rendersBareHTML(caseName: String) throws {
        let source = try String(contentsOf: Self.goldenDirectory.appending(path: "\(caseName).md"), encoding: .utf8)
        let expected = try String(contentsOf: Self.goldenDirectory.appending(path: "\(caseName).html"), encoding: .utf8)

        #expect(BareHTML.render(source) == expected.trimmingTrailingNewlines())
    }

    @Test func goldenDirectoryIsNotEmpty() {
        #expect(!Self.caseNames.isEmpty)
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}

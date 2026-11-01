import Foundation
import Testing
import MarkdownCore

/// Each `Golden/<options>/<name>.md` is rendered with those options and compared
/// with `<name>.html`. Add a case by dropping in a new pair of files.
struct GoldenTests {
    struct Case: CustomTestStringConvertible, Sendable {
        let folder: String
        let name: String
        var testDescription: String { "\(folder)/\(name)" }
    }

    static let goldenDirectory = Bundle.module.resourceURL!.appending(path: "Golden")

    /// Folder name → the options its cases render with.
    static let optionsByFolder: [String: RenderOptions] = [
        "plain": .plain,
        "default": .default,
    ]

    static var cases: [Case] {
        optionsByFolder.keys.sorted().flatMap { folder in
            let path = goldenDirectory.appending(path: folder).path()
            let files = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            return files.filter { $0.hasSuffix(".md") }.sorted().map { Case(folder: folder, name: String($0.dropLast(3))) }
        }
    }

    @Test(arguments: cases)
    func rendersBareHTML(_ golden: Case) throws {
        let folder = Self.goldenDirectory.appending(path: golden.folder)
        let source = try String(contentsOf: folder.appending(path: "\(golden.name).md"), encoding: .utf8)
        let expected = try String(contentsOf: folder.appending(path: "\(golden.name).html"), encoding: .utf8)

        #expect(BareHTML.render(source, options: Self.optionsByFolder[golden.folder]!) == expected.trimmingTrailingNewlines())
    }

    @Test func everyOptionsFolderHasCases() {
        for folder in Self.optionsByFolder.keys {
            #expect(Self.cases.contains { $0.folder == folder }, "Golden/\(folder) has no cases")
        }
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.hasSuffix("\n") { result.removeLast() }
        return result
    }
}

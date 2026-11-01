import Foundation
import Testing
@testable import MarkdownCore

struct EditorHistoryTests {
    @Test func editorJavaScriptKeepsTheMinimumDepth() throws {
        #expect(EditorHistory.minimumDepth == 10_000)
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("SkinnyDip/Editor/web/src/editor.js")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("\(EditorHistory.minimumDepth)"))
    }
}

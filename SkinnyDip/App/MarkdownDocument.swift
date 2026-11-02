import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// A `.md` file. The text is the Markdown Source, read and written unchanged (ADR-0002).
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]
    static let writableContentTypes: [UTType] = [.markdown]

    var source: String
    /// In memory only. Never written into the `.md` (ADR-0007).
    var scratchID: UUID?
    var undoHistory: String?
    var pinnedTitle: String?
    var createdAt: Date

    init(
        source: String = "",
        scratchID: UUID? = nil,
        undoHistory: String? = nil,
        pinnedTitle: String? = nil,
        createdAt: Date = Date()
    ) {
        self.source = source
        self.scratchID = scratchID
        self.undoHistory = undoHistory
        self.pinnedTitle = pinnedTitle
        self.createdAt = createdAt
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let source = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        self.source = source
        self.scratchID = nil
        self.undoHistory = nil
        self.pinnedTitle = nil
        self.createdAt = Date()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(source.utf8))
    }
}

import Foundation

/// Sidecar for a Scratch Document. `undoHistory` is CodeMirror JSON, carried
/// untouched by the store (ADR-0007).
public struct ScratchMeta: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
    public var windowIndex: Int
    public var tabIndex: Int
    public var undoHistory: String?

    public init(
        createdAt: Date,
        updatedAt: Date,
        closedAt: Date? = nil,
        windowIndex: Int,
        tabIndex: Int,
        undoHistory: String? = nil
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.windowIndex = windowIndex
        self.tabIndex = tabIndex
        self.undoHistory = undoHistory
    }

    public static func recovered(now: Date) -> ScratchMeta {
        ScratchMeta(createdAt: now, updatedAt: now, windowIndex: 0, tabIndex: 0)
    }
}

public enum ScratchStoreError: Error, Equatable {
    case notFound
}

/// Scratch Documents on disk: `<root>/<uuid>.md` plus a JSON sidecar, and
/// Recently Closed under `<root>/Closed/`. The root and the clock are injected
/// so tests use a temporary directory. Writes are atomic.
public final class ScratchStore: @unchecked Sendable {
    private let root: URL
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(root: URL, now: @escaping @Sendable () -> Date = Date.init) {
        self.root = root
        self.now = now
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        self.decoder = decoder
    }

    public func save(id: UUID, text: String, meta: ScratchMeta) throws {
        try perform {
            if text.isEmpty {
                try remove(id: id, in: root)
                return
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try atomicWrite(Data(text.utf8), to: markdownURL(id, in: root))
            try atomicWrite(try encoder.encode(meta), to: sidecarURL(id, in: root))
        }
    }

    public func open() throws -> [(id: UUID, text: String, meta: ScratchMeta)] {
        try perform {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            var documents: [(id: UUID, text: String, meta: ScratchMeta)] = []
            for url in urls {
                guard url.pathExtension == "md", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                    continue
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let meta = readMeta(id: id, in: root) ?? .recovered(now: now())
                documents.append((id: id, text: text, meta: meta))
            }
            documents.sort { lhs, rhs in
                if lhs.meta.windowIndex != rhs.meta.windowIndex {
                    return lhs.meta.windowIndex < rhs.meta.windowIndex
                }
                return lhs.meta.tabIndex < rhs.meta.tabIndex
            }
            return documents
        }
    }

    /// Moves a non-empty scratch into `Closed/` and stamps `closedAt`. Missing or
    /// empty documents are left alone.
    public func close(id: UUID) throws {
        try perform {
            let source = markdownURL(id, in: root)
            guard FileManager.default.fileExists(atPath: source.path) else { return }
            let text = (try? String(contentsOf: source, encoding: .utf8)) ?? ""
            if text.isEmpty {
                try remove(id: id, in: root)
                return
            }
            var meta = readMeta(id: id, in: root) ?? .recovered(now: now())
            meta.closedAt = now()
            let closed = closedDirectory()
            try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
            try moveReplacing(source, to: markdownURL(id, in: closed))
            let sidecar = sidecarURL(id, in: root)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try moveReplacing(sidecar, to: sidecarURL(id, in: closed))
            }
            try atomicWrite(try encoder.encode(meta), to: sidecarURL(id, in: closed))
        }
    }

    public func recentlyClosed(limit: Int = 20) throws -> [(id: UUID, title: String, closedAt: Date)] {
        try perform {
            let closed = closedDirectory()
            guard FileManager.default.fileExists(atPath: closed.path) else { return [] }
            let urls = try FileManager.default.contentsOfDirectory(at: closed, includingPropertiesForKeys: nil)
            var entries: [(id: UUID, title: String, closedAt: Date)] = []
            for url in urls {
                guard url.pathExtension == "md", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
                    continue
                }
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let meta = readMeta(id: id, in: closed) ?? .recovered(now: now())
                let closedAt = meta.closedAt ?? now()
                entries.append((id: id, title: DocumentTitle.suggested(from: text), closedAt: closedAt))
            }
            entries.sort { $0.closedAt > $1.closedAt }
            return Array(entries.prefix(max(0, limit)))
        }
    }

    public func reopen(id: UUID) throws -> (text: String, meta: ScratchMeta) {
        try perform {
            let closed = closedDirectory()
            let source = markdownURL(id, in: closed)
            guard FileManager.default.fileExists(atPath: source.path) else { throw ScratchStoreError.notFound }
            let text = try String(contentsOf: source, encoding: .utf8)
            var meta = readMeta(id: id, in: closed) ?? .recovered(now: now())
            meta.closedAt = nil
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try moveReplacing(source, to: markdownURL(id, in: root))
            let sidecar = sidecarURL(id, in: closed)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try? FileManager.default.removeItem(at: sidecar)
            }
            try atomicWrite(try encoder.encode(meta), to: sidecarURL(id, in: root))
            return (text, meta)
        }
    }

    public func discard(id: UUID) throws {
        try perform {
            try remove(id: id, in: root)
            try remove(id: id, in: closedDirectory())
        }
    }

    public func purgeClosed(olderThan days: Int = 30) throws {
        try perform {
            let closed = closedDirectory()
            guard FileManager.default.fileExists(atPath: closed.path) else { return }
            let cutoff = now().addingTimeInterval(-Double(days) * 24 * 60 * 60)
            let urls = try FileManager.default.contentsOfDirectory(at: closed, includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension == "md" {
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { continue }
                guard let closedAt = readMeta(id: id, in: closed)?.closedAt, closedAt < cutoff else { continue }
                try remove(id: id, in: closed)
            }
        }
    }

    private func perform<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func closedDirectory() -> URL {
        root.appendingPathComponent("Closed", isDirectory: true)
    }

    private func markdownURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).md")
    }

    private func sidecarURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func readMeta(id: UUID, in directory: URL) -> ScratchMeta? {
        let url = sidecarURL(id, in: directory)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ScratchMeta.self, from: data)
    }

    private func remove(id: UUID, in directory: URL) throws {
        let fileManager = FileManager.default
        for url in [markdownURL(id, in: directory), sidecarURL(id, in: directory)] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let temporary = url.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        try moveReplacing(temporary, to: url)
    }

    private func moveReplacing(_ source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: source)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }
}

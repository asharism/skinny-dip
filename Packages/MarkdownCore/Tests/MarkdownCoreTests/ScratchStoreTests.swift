import Foundation
import Testing
@testable import MarkdownCore

struct ScratchStoreTests {
    @Test func roundTripSortsByWindowThenTab() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, _) = try makeStore(now: now)
        let first = UUID()
        let second = UUID()
        let third = UUID()
        try store.save(id: second, text: "second", meta: meta(now, window: 1, tab: 0))
        try store.save(id: third, text: "third", meta: meta(now, window: 0, tab: 1))
        try store.save(id: first, text: "first", meta: meta(now, window: 0, tab: 0))
        let opened = try store.open()
        #expect(opened.map(\.id) == [first, third, second])
        #expect(opened.map(\.text) == ["first", "third", "second"])
        #expect(opened[0].meta == meta(now, window: 0, tab: 0))
    }

    @Test func emptyTextDeletesTheDocument() throws {
        let (store, _) = try makeStore()
        let id = UUID()
        try store.save(id: id, text: "hello", meta: meta(Date(timeIntervalSince1970: 10), window: 0, tab: 0))
        try store.save(id: id, text: "", meta: meta(Date(timeIntervalSince1970: 10), window: 0, tab: 0))
        #expect(try store.open().isEmpty)
    }

    @Test func writesAreAtomicAndStaleTemporaryFilesAreIgnored() throws {
        let (store, root) = try makeStore()
        let id = UUID()
        try store.save(id: id, text: "kept", meta: meta(Date(timeIntervalSince1970: 10), window: 0, tab: 0))
        let stale = root.appendingPathComponent("\(UUID().uuidString).md.tmp")
        try Data("nope".utf8).write(to: stale)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.allSatisfy { !$0.hasSuffix(".tmp") || $0 == stale.lastPathComponent })
        #expect(!names.contains { $0.hasSuffix(".md.tmp") && $0 != stale.lastPathComponent })
        let opened = try store.open()
        #expect(opened.map(\.text) == ["kept"])
    }

    @Test func closeMovesIntoRecentlyClosedNewestFirst() throws {
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        let (store, root) = try makeStore(now: clock.date, clock: { clock.date })
        let older = UUID()
        let newer = UUID()
        try store.save(id: older, text: "# Weekly status — Payments", meta: meta(clock.date, window: 0, tab: 0))
        try store.close(id: older)
        clock.date = clock.date.addingTimeInterval(60)
        try store.save(id: newer, text: "Shipped", meta: meta(clock.date, window: 0, tab: 1))
        try store.close(id: newer)
        #expect(try store.open().isEmpty)
        let closed = root.appendingPathComponent("Closed")
        #expect(FileManager.default.fileExists(atPath: closed.appendingPathComponent("\(older.uuidString).md").path))
        let recent = try store.recentlyClosed(limit: 20)
        #expect(recent.map(\.id) == [newer, older])
        #expect(recent.map(\.title) == ["Shipped", "Weekly status — Payments"])
        #expect(recent[0].closedAt == clock.date)
        let limited = try store.recentlyClosed(limit: 1)
        #expect(limited.map(\.id) == [newer])
    }

    @Test func closeOfEmptyOrMissingIsANoOp() throws {
        let (store, _) = try makeStore()
        try store.close(id: UUID())
        let empty = UUID()
        try store.save(id: empty, text: "", meta: meta(Date(timeIntervalSince1970: 10), window: 0, tab: 0))
        try store.close(id: empty)
        #expect(try store.recentlyClosed().isEmpty)
    }

    @Test func reopenMovesTheFileBackAndASecondReopenThrows() throws {
        let (store, root) = try makeStore()
        let id = UUID()
        try store.save(id: id, text: "back", meta: meta(Date(timeIntervalSince1970: 10), window: 2, tab: 3, history: "hist"))
        try store.close(id: id)
        let restored = try store.reopen(id: id)
        #expect(restored.text == "back")
        #expect(restored.meta.closedAt == nil)
        #expect(restored.meta.undoHistory == "hist")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(id.uuidString).md").path))
        #expect(throws: ScratchStoreError.notFound) {
            try store.reopen(id: id)
        }
    }

    @Test func purgeClosedRemovesOnlyOldEntries() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(date: now)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ScratchStore(root: root, now: { clock.date })
        let stale = UUID()
        let fresh = UUID()
        clock.date = now.addingTimeInterval(-31 * 86_400)
        try store.save(id: stale, text: "old", meta: meta(clock.date, window: 0, tab: 0))
        try store.close(id: stale)
        clock.date = now
        try store.save(id: fresh, text: "new", meta: meta(now, window: 0, tab: 1))
        try store.close(id: fresh)
        try store.purgeClosed(olderThan: 30)
        #expect(try store.recentlyClosed().map(\.id) == [fresh])
    }

    @Test func discardRemovesOpenAndClosedCopies() throws {
        let (store, _) = try makeStore()
        let id = UUID()
        try store.save(id: id, text: "gone", meta: meta(Date(timeIntervalSince1970: 10), window: 0, tab: 0))
        try store.discard(id: id)
        #expect(try store.open().isEmpty)
        try store.save(id: id, text: "gone", meta: meta(Date(timeIntervalSince1970: 10), window: 0, tab: 0))
        try store.close(id: id)
        try store.discard(id: id)
        #expect(try store.recentlyClosed().isEmpty)
    }

    @Test func corruptSidecarStillReturnsTheText() throws {
        let clock = Date(timeIntervalSince1970: 1_700_000_000)
        let (store, root) = try makeStore(now: clock)
        let id = UUID()
        try store.save(id: id, text: "readable", meta: meta(clock, window: 4, tab: 5))
        try Data("{".utf8).write(to: root.appendingPathComponent("\(id.uuidString).json"))
        let opened = try store.open()
        #expect(opened.count == 1)
        #expect(opened[0].text == "readable")
        #expect(opened[0].meta.windowIndex == 0)
        #expect(opened[0].meta.tabIndex == 0)
        #expect(opened[0].meta.undoHistory == nil)
        #expect(opened[0].meta.createdAt == clock)
    }

    @Test func missingMarkdownIsSkipped() throws {
        let (store, root) = try makeStore()
        let id = UUID()
        try Data("{}".utf8).write(to: root.appendingPathComponent("\(id.uuidString).json"))
        #expect(try store.open().isEmpty)
    }

    @Test func roundTripsALargeUndoHistory() throws {
        let (store, _) = try makeStore()
        let id = UUID()
        let history = String(repeating: "x", count: 1_000_000)
        try store.save(id: id, text: "body", meta: meta(Date(timeIntervalSince1970: 10), window: 0, tab: 0, history: history))
        #expect(try store.open().first?.meta.undoHistory == history)
    }

    @Test func mismatchedHistoryIsDropped() {
        let json = #"{"doc":"hello","history":[]}"#
        #expect(ScratchRestore.history(forText: "hello", storedHistoryJSON: json) == json)
        #expect(ScratchRestore.history(forText: "edited by hand", storedHistoryJSON: json) == nil)
        #expect(ScratchRestore.history(forText: "hello", storedHistoryJSON: "not json") == nil)
    }

    private func makeStore(
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        clock: (@Sendable () -> Date)? = nil
    ) throws -> (ScratchStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scratch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ScratchStore(root: root, now: clock ?? { now })
        return (store, root)
    }

    private func meta(_ date: Date, window: Int, tab: Int, history: String? = nil) -> ScratchMeta {
        ScratchMeta(createdAt: date, updatedAt: date, windowIndex: window, tabIndex: tab, undoHistory: history)
    }

}

private final class TestClock: @unchecked Sendable {
    var date: Date
    init(date: Date) { self.date = date }
}

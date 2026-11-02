#if os(macOS)
import AppKit
import Foundation
import MarkdownCore

extension Notification.Name {
    static let tabsDidChange = Notification.Name("skinnyDipTabsDidChange")
    static let duplicateDocument = Notification.Name("skinnyDipDuplicateDocument")
    static let selectTab = Notification.Name("skinnyDipSelectTab")
}

@MainActor
final class ScratchSession: ObservableObject {
    static let shared = ScratchSession()

    let store: ScratchStore
    @Published private(set) var recentlyClosed: [(id: UUID, title: String, closedAt: Date)] = []
    @Published private(set) var unflushed: Set<UUID> = []

    private var queue: [Queued] = []
    private var pendingRestore = false
    private(set) var isTerminating = false
    private var lives: [UUID: Live] = [:]
    private var scratchByWindow: [ObjectIdentifier: UUID] = [:]
    private var openDocuments: [ObjectIdentifier: OpenDocument] = [:]
    private var preparedCloses = Set<ObjectIdentifier>()
    private var didInstallHook = false
    private var loggedOversizedHistory = false

    struct Queued {
        var id: UUID
        var text: String
        var meta: ScratchMeta
        var pinnedTitle: String?
    }

    struct Live {
        var text: String
        var createdAt: Date
        var undoHistory: String?
        var controller: EditorController?
        weak var window: NSWindow?
    }

    struct OpenDocument {
        var text: String
        var fileName: String?
        var suggested: String
        var scratchID: UUID?
    }

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let root = base
            .appendingPathComponent("Skinny Dip", isDirectory: true)
            .appendingPathComponent("Scratch", isDirectory: true)
        store = ScratchStore(root: root)
    }

    /// Saves a scratch before AppKit closes the window. The original close runs
    /// afterwards, so the tab still goes away.
    func installCloseHook() {
        guard !didInstallHook else { return }
        didInstallHook = true
        guard let method = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.performClose(_:))) else { return }
        let original = method_getImplementation(method)
        typealias PerformClose = @convention(c) (AnyObject, Selector, Any?) -> Void
        let perform = unsafeBitCast(original, to: PerformClose.self)
        let block: @convention(block) (NSWindow, Any?) -> Void = { window, sender in
            if window.tabbingIdentifier == "SkinnyDipDocument" {
                ScratchSession.shared.prepareForClose(window: window)
            }
            perform(window, #selector(NSWindow.performClose(_:)), sender)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    func prepareLaunch() {
        try? store.purgeClosed(olderThan: 30)
        pendingRestore = ((try? store.open()) ?? []).isEmpty == false
        refreshClosed()
    }

    var shouldOpenUntitled: Bool { !pendingRestore }

    func openRestoredDocuments() {
        let documents = (try? store.open()) ?? []
        pendingRestore = false
        guard !documents.isEmpty else { return }
        let groups = Dictionary(grouping: documents, by: \.meta.windowIndex)
        let previous = NSWindow.allowsAutomaticWindowTabbing
        for key in groups.keys.sorted() {
            let tabs = groups[key, default: []].sorted { $0.meta.tabIndex < $1.meta.tabIndex }
            // At launch the first window is not key yet, so `NSApp.keyWindow` is nil and
            // every later tab opened as a window of its own. Hold on to the new window.
            var host: NSWindow?
            for (index, tab) in tabs.enumerated() {
                queue = [Queued(id: tab.id, text: tab.text, meta: tab.meta, pinnedTitle: nil)]
                let before = Set(NSApp.windows.map(ObjectIdentifier.init))
                NSWindow.allowsAutomaticWindowTabbing = index != 0
                DocumentTabs.newDocument(in: index == 0 ? nil : host)
                if host == nil {
                    host = NSApp.windows.first {
                        !before.contains(ObjectIdentifier($0)) && $0.windowController?.document is NSDocument
                    }
                }
            }
            if let first = host?.tabGroup?.windows.first {
                first.tabGroup?.selectedWindow = first
            }
        }
        NSWindow.allowsAutomaticWindowTabbing = previous
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
    }

    /// `DocumentGroup`'s new-document closure. AppKit opens existing files on
    /// its "NSDocumentController Opening" queue and SwiftUI still asks for a new
    /// document there; that placeholder is replaced by the file's contents, so
    /// off main it must not touch the Scratch queue (or assume the main actor).
    nonisolated static func makeDocumentForGroup() -> MarkdownDocument {
        guard Thread.isMainThread else { return MarkdownDocument() }
        return MainActor.assumeIsolated { shared.makeNewDocument() }
    }

    func makeNewDocument() -> MarkdownDocument {
        if !queue.isEmpty {
            let next = queue.removeFirst()
            return MarkdownDocument(
                source: next.text,
                scratchID: next.id,
                undoHistory: next.meta.undoHistory,
                pinnedTitle: next.pinnedTitle,
                createdAt: next.meta.createdAt
            )
        }
        return MarkdownDocument(source: "", scratchID: UUID(), createdAt: Date())
    }

    func attach(
        scratchID: UUID?,
        text: String,
        createdAt: Date,
        controller: EditorController,
        window: NSWindow,
        fileName: String?,
        suggested: String
    ) {
        let key = ObjectIdentifier(window)
        openDocuments[key] = OpenDocument(text: text, fileName: fileName, suggested: suggested, scratchID: scratchID)
        guard let scratchID else {
            window.isRestorable = true
            return
        }
        var live = lives[scratchID] ?? Live(text: text, createdAt: createdAt, undoHistory: nil, controller: controller, window: window)
        live.text = text
        live.controller = controller
        live.window = window
        lives[scratchID] = live
        scratchByWindow[key] = scratchID
        window.isRestorable = false
    }

    func noteText(scratchID: UUID?, window: NSWindow?, text: String, suggested: String, fileName: String?) {
        if let window {
            openDocuments[ObjectIdentifier(window)] = OpenDocument(
                text: text,
                fileName: fileName,
                suggested: suggested,
                scratchID: scratchID
            )
        }
        guard let scratchID, var live = lives[scratchID] else { return }
        live.text = text
        lives[scratchID] = live
        unflushed.insert(scratchID)
    }

    func flush(id: UUID, history: String?) {
        guard var live = lives[id] else { return }
        live.undoHistory = capped(history)
        lives[id] = live
        let placement = placement(of: live.window)
        let meta = ScratchMeta(
            createdAt: live.createdAt,
            updatedAt: Date(),
            windowIndex: placement.window,
            tabIndex: placement.tab,
            undoHistory: live.undoHistory
        )
        let text = live.text
        let store = store
        Task.detached {
            try? store.save(id: id, text: text, meta: meta)
        }
        unflushed.remove(id)
    }

    func prepareForClose(window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard window.tabbingIdentifier == "SkinnyDipDocument" || scratchByWindow[key] != nil else { return }
        guard preparedCloses.insert(key).inserted else { return }
        if let id = scratchByWindow[key], var live = lives[id] {
            // Do not export history here. That spins the run loop inside
            // performClose, and AppKit then abandons the close.
            if let history = live.undoHistory {
                live.undoHistory = capped(history)
                lives[id] = live
            }
            let placement = placement(of: window)
            let meta = ScratchMeta(
                createdAt: live.createdAt,
                updatedAt: Date(),
                windowIndex: placement.window,
                tabIndex: placement.tab,
                undoHistory: live.undoHistory
            )
            try? store.save(id: id, text: live.text, meta: meta)
            (window.windowController?.document as? NSDocument)?.updateChangeCount(.changeCleared)
            return
        }
        if let document = window.windowController?.document as? NSDocument,
           let url = document.fileURL,
           document.isDocumentEdited {
            try? document.write(to: url, ofType: document.fileType ?? "net.daringfireball.markdown")
            document.updateChangeCount(.changeCleared)
        }
    }

    func windowWillClose(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        defer {
            openDocuments[key] = nil
            preparedCloses.remove(key)
            NotificationCenter.default.post(name: .tabsDidChange, object: nil)
        }
        guard let id = scratchByWindow.removeValue(forKey: key), let live = lives.removeValue(forKey: id) else { return }
        if !isTerminating, !live.text.isEmpty {
            try? store.close(id: id)
            refreshClosed()
        }
        unflushed.remove(id)
    }

    func terminate() -> NSApplication.TerminateReply {
        isTerminating = true
        for (id, var live) in lives {
            if let history = live.controller?.exportHistoryBlocking() {
                live.undoHistory = capped(history)
            }
            let placement = placement(of: live.window)
            let meta = ScratchMeta(
                createdAt: live.createdAt,
                updatedAt: Date(),
                windowIndex: placement.window,
                tabIndex: placement.tab,
                undoHistory: live.undoHistory
            )
            try? store.save(id: id, text: live.text, meta: meta)
            (live.window?.windowController?.document as? NSDocument)?.updateChangeCount(.changeCleared)
            lives[id] = live
        }
        return .terminateNow
    }

    func discardScratch(id: UUID) {
        try? store.discard(id: id)
        lives[id] = nil
        unflushed.remove(id)
        scratchByWindow = scratchByWindow.filter { $0.value != id }
    }

    func reopenMostRecent() {
        guard let newest = recentlyClosed.first else { return }
        reopen(id: newest.id)
    }

    func reopen(id: UUID) {
        guard let restored = try? store.reopen(id: id) else { return }
        queue.append(Queued(id: id, text: restored.text, meta: restored.meta, pinnedTitle: nil))
        DocumentTabs.newDocument(in: NSApp.keyWindow)
        refreshClosed()
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
    }

    func duplicate(window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let document = openDocuments[key] else { return }
        let title = DocumentTitle.duplicateTitle(fileName: document.fileName, suggested: document.suggested)
        let group = window.tabGroup
        let before = Set((group?.windows ?? [window]).map { ObjectIdentifier($0) })
        let currentIndex = group?.windows.firstIndex(where: { $0 === window }) ?? 0
        queue.append(Queued(
            id: UUID(),
            text: document.text,
            meta: ScratchMeta(createdAt: Date(), updatedAt: Date(), windowIndex: 0, tabIndex: 0),
            pinnedTitle: title
        ))
        DocumentTabs.newDocument(in: window, at: currentIndex + 1)
        guard let group else { return }
        guard let newWindow = group.windows.first(where: { !before.contains(ObjectIdentifier($0)) }) else { return }
        let from = group.windows.firstIndex(where: { $0 === newWindow }) ?? 0
        let destination = min(currentIndex + 1, max(group.windows.count - 1, 0))
        if from != destination {
            group.removeWindow(newWindow)
            group.insertWindow(newWindow, at: min(destination, group.windows.count))
        }
        group.selectedWindow = newWindow
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
    }

    func isUnflushed(_ window: NSWindow) -> Bool {
        guard let id = scratchByWindow[ObjectIdentifier(window)] else { return false }
        return unflushed.contains(id)
    }

    func refreshClosed() {
        recentlyClosed = (try? store.recentlyClosed(limit: 20)) ?? []
    }

    private func capped(_ history: String?) -> String? {
        guard let history else { return nil }
        if history.utf8.count > 8 * 1024 * 1024 {
            if !loggedOversizedHistory {
                loggedOversizedHistory = true
                fputs("[SkinnyDip] scratch undo history exceeds 8 MB; saving text only\n", stderr)
            }
            return nil
        }
        return history
    }

    private func placement(of window: NSWindow?) -> (window: Int, tab: Int) {
        guard let window else { return (0, 0) }
        let documentWindows = NSApp.windows
            .filter { $0.tabbingIdentifier == "SkinnyDipDocument" }
            .sorted { $0.windowNumber < $1.windowNumber }
        var groups: [NSWindowTabGroup] = []
        for candidate in documentWindows {
            guard let group = candidate.tabGroup else { continue }
            if !groups.contains(where: { $0 === group }) { groups.append(group) }
        }
        let windowIndex = groups.firstIndex(where: { $0 === window.tabGroup }) ?? 0
        let tabIndex = window.tabGroup?.windows.firstIndex(where: { $0 === window }) ?? 0
        return (windowIndex, tabIndex)
    }
}

extension NSWindow {
    /// File ▸ Close already closes a tab. ⌘W and the tab ✕ call the same method
    /// after saving, so AppKit does not ask about a scratch document.
    func closeDocumentWindow() {
        ScratchSession.shared.prepareForClose(window: self)
        performClose(standardWindowButton(.closeButton) ?? self)
    }
}
#endif

#if os(macOS)
import AppKit
import Foundation

/// Mirrors `NSWindow.tabGroup` for one document window. The Tab strip reads this
/// and never talks to AppKit itself (ADR-0005).
@MainActor
final class WindowTabModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: ObjectIdentifier
        var title: String
        var isEdited: Bool
        var isSelected: Bool
    }

    @Published private(set) var items: [Item] = []
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        DocumentTabs.configure(window)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            },
            NotificationCenter.default.addObserver(forName: .tabsDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            },
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] note in
                guard let closing = note.object as? NSWindow else { return }
                Task { @MainActor in
                    ScratchSession.shared.windowWillClose(closing)
                    self?.refresh()
                }
            },
        ]
        refresh()
    }

    func refresh() {
        guard let window else { return }
        if window.tabGroup?.isTabBarVisible == true {
            window.toggleTabBar(nil)
        }
        let windows = window.tabGroup?.windows ?? [window]
        let selected = window.tabGroup?.selectedWindow ?? window
        let next = windows.map { candidate in
            let document = candidate.windowController?.document as? NSDocument
            let edited = (document?.isDocumentEdited ?? false) || ScratchSession.shared.isUnflushed(candidate)
            let title = candidate.title.isEmpty ? "Untitled" : candidate.title
            return Item(
                id: ObjectIdentifier(candidate),
                title: title,
                isEdited: edited,
                isSelected: candidate === selected
            )
        }
        if next != items { items = next }
    }

    func select(_ id: ObjectIdentifier) {
        guard let group = window?.tabGroup else { return }
        group.selectedWindow = group.windows.first { ObjectIdentifier($0) == id }
        refresh()
    }

    func selectIndex(_ oneBased: Int) {
        guard let windows = window?.tabGroup?.windows, !windows.isEmpty else { return }
        let index = oneBased == 9 ? windows.count - 1 : min(oneBased, windows.count) - 1
        guard windows.indices.contains(index) else { return }
        window?.tabGroup?.selectedWindow = windows[index]
        refresh()
    }

    func close(_ id: ObjectIdentifier) {
        guard let target = window(for: id) else { return }
        if target.tabGroup?.selectedWindow !== target {
            target.tabGroup?.selectedWindow = target
        }
        target.closeDocumentWindow()
    }

    func closeOthers(keeping id: ObjectIdentifier) {
        guard let windows = window?.tabGroup?.windows else { return }
        for candidate in windows where ObjectIdentifier(candidate) != id {
            candidate.closeDocumentWindow()
        }
    }

    func move(from: Int, to: Int) {
        guard let group = window?.tabGroup else { return }
        let windows = group.windows
        guard windows.indices.contains(from), to >= 0 else { return }
        let moving = windows[from]
        let destination = min(to, windows.count - 1)
        guard destination != from else { return }
        group.removeWindow(moving)
        group.insertWindow(moving, at: min(destination, group.windows.count))
        group.selectedWindow = moving
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
        refresh()
    }

    func moveToNewWindow(_ id: ObjectIdentifier) {
        DocumentTabs.beginDetachedWindow()
        window(for: id)?.moveTabToNewWindow(nil)
        DocumentTabs.endDetachedWindow()
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
    }

    func window(for id: ObjectIdentifier) -> NSWindow? {
        let windows = window?.tabGroup?.windows ?? []
        return windows.first { ObjectIdentifier($0) == id } ?? (window.map { ObjectIdentifier($0) == id ? $0 : nil } ?? nil)
    }

    func newTab() {
        DocumentTabs.newDocument(in: window ?? DocumentTabs.frontDocumentWindow())
    }

    func closeToTheRight(of id: ObjectIdentifier) {
        guard let windows = window?.tabGroup?.windows,
              let index = windows.firstIndex(where: { ObjectIdentifier($0) == id }) else { return }
        for candidate in windows[(index + 1)...] {
            candidate.closeDocumentWindow()
        }
    }

    func duplicate(_ id: ObjectIdentifier) {
        guard let target = window(for: id) else { return }
        ScratchSession.shared.duplicate(window: target)
    }
}
#endif

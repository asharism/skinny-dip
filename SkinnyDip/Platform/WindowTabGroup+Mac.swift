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
    /// The gap a Tab dragged from another window would land in, while one hovers here.
    @Published var dropSlot: Int?
    private(set) weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    /// AppKit's own tab commands (Merge All Windows, Move Tab to New Window, the
    /// Window menu) change the group without telling us; watch it directly.
    private var groupWatch: [NSKeyValueObservation] = []
    /// The strip in SwiftUI's window coordinates (top-left origin), and one Tab's width.
    private var stripFrame: CGRect = .zero
    private var tabWidth: CGFloat = 0
    private var stripInset: CGFloat = 0

    /// Every model with a window, so a drag can find the strip under the pointer.
    private static let all = NSHashTable<WindowTabModel>.weakObjects()

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        Self.all.add(self)
        DocumentTabs.adoptIfNeeded(window)
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
        watchGroup()
        refresh()
    }

    private func watchGroup() {
        guard let window else { return }
        groupWatch = [
            window.observe(\.tabGroup, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.watchGroup()
                    self?.groupChanged()
                }
            },
        ]
        if let group = window.tabGroup {
            groupWatch.append(group.observe(\.windows, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.groupChanged() }
            })
            groupWatch.append(group.observe(\.isTabBarVisible, options: [.new]) { [weak self] group, _ in
                guard group.isTabBarVisible else { return }
                Task { @MainActor in self?.groupChanged() }
            })
        }
    }

    private var groupChangePending = false

    /// One refresh per run-loop turn, however many changes AppKit reports.
    private func groupChanged() {
        guard !groupChangePending else { return }
        groupChangePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            groupChangePending = false
            guard let window else { return }
            // Only the Tab on show has a title bar to clean up.
            if (window.tabGroup?.selectedWindow ?? window) === window {
                DocumentTabs.hideNativeTabBar(window)
            }
            refresh()
        }
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

    /// `grabbedAt`, in screen coordinates, is where a drag let go: the new window
    /// is placed with its Tab under that point.
    func moveToNewWindow(_ id: ObjectIdentifier, grabbedAt: NSPoint? = nil) {
        guard let moving = window(for: id), (moving.tabGroup?.windows.count ?? 1) > 1 else { return }
        // Where the first Tab sits in the window, measured before the move.
        let grab = screenStrip.map { strip in
            NSPoint(x: strip.frame.minX - moving.frame.minX + strip.inset + strip.tabWidth / 2,
                    y: moving.frame.maxY - strip.frame.midY)
        }
        DocumentTabs.beginDetachedWindow()
        moving.moveTabToNewWindow(nil)
        DocumentTabs.endDetachedWindow()
        if let grabbedAt, let grab {
            var frame = moving.frame
            frame.origin = NSPoint(x: grabbedAt.x - grab.x, y: grabbedAt.y + grab.y - frame.height)
            moving.setFrame(moving.constrainFrameRect(frame, to: moving.screen ?? NSScreen.main), display: true)
        }
        moving.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
    }

    // MARK: Moving Tabs between Windows

    /// `frame` nil keeps the last one.
    func noteStrip(frame: CGRect?, tabWidth: CGFloat, inset: CGFloat) {
        if let frame { stripFrame = frame }
        self.tabWidth = tabWidth
        stripInset = inset
    }

    /// This window's strip in screen coordinates.
    var screenStrip: TabDrop.Strip? {
        guard let window, let content = window.contentView, stripFrame.width > 0 else { return nil }
        let y = content.isFlipped ? stripFrame.minY : content.bounds.height - stripFrame.maxY
        let inView = NSRect(x: stripFrame.minX, y: y, width: stripFrame.width, height: stripFrame.height)
        let screen = window.convertToScreen(content.convert(inView, to: nil))
        return TabDrop.Strip(frame: screen, tabWidth: tabWidth, inset: stripInset, count: items.count)
    }

    /// The strip shown in `window`'s title bar, in screen coordinates.
    static func screenStrip(of window: NSWindow) -> TabDrop.Strip? {
        all.allObjects.first { $0.window === window }?.screenStrip
    }

    /// The other windows' visible strips, front to back.
    private func otherStrips() -> [(model: WindowTabModel, strip: TabDrop.Strip)] {
        let own = window?.tabGroup?.windows ?? window.map { [$0] } ?? []
        let models = Self.all.allObjects
        return NSApp.orderedWindows.compactMap { candidate in
            guard candidate.isVisible, !candidate.isMiniaturized,
                  !own.contains(where: { $0 === candidate }),
                  (candidate.tabGroup?.selectedWindow ?? candidate) === candidate,
                  let model = models.first(where: { $0.window === candidate }),
                  let strip = model.screenStrip else { return nil }
            return (model, strip)
        }
    }

    /// Where a Tab let go at `point` (screen coordinates) would land.
    func drop(at point: NSPoint, detachDistance: CGFloat) -> (TabDrop, WindowTabModel?) {
        guard let own = screenStrip else { return (.reorder, nil) }
        let others = otherStrips()
        let result = TabDrop.resolve(point: point, own: own, detachDistance: detachDistance, others: others.map(\.strip))
        if case .join(let target, _) = result { return (result, others[target].model) }
        return (result, nil)
    }

    /// While dragging: shows the landing gap in whichever other strip is under the pointer.
    func dragMoved(to point: NSPoint, detachDistance: CGFloat) {
        let (result, target) = drop(at: point, detachDistance: detachDistance)
        for model in Self.all.allObjects where model !== target && model.dropSlot != nil {
            model.dropSlot = nil
        }
        if case .join(_, let slot) = result, target?.dropSlot != slot { target?.dropSlot = slot }
    }

    func dragEnded() {
        for model in Self.all.allObjects where model.dropSlot != nil { model.dropSlot = nil }
    }

    /// Moves a Tab into `target`'s window before Tab `slot`. A window left with no
    /// Tabs goes away, as the Tab was the window.
    func join(_ id: ObjectIdentifier, to target: WindowTabModel, at slot: Int) {
        guard let moving = window(for: id), let host = target.window?.tabGroup?.selectedWindow ?? target.window,
              host.tabGroup?.windows.contains(where: { $0 === moving }) != true else { return }
        let source = moving.tabGroup
        if let source, source.windows.count > 1 {
            // Keep the source window showing a neighbour, not an empty frame.
            let rest = source.windows.filter { $0 !== moving }
            let index = source.windows.firstIndex(where: { $0 === moving }) ?? 0
            source.removeWindow(moving)
            source.selectedWindow = rest[min(index, rest.count - 1)]
        }
        host.addTabbedWindow(moving, ordered: .above)
        if let group = host.tabGroup {
            let destination = min(max(0, slot), group.windows.count - 1)
            if group.windows.firstIndex(where: { $0 === moving }) != destination {
                group.removeWindow(moving)
                group.insertWindow(moving, at: min(destination, group.windows.count))
            }
            group.selectedWindow = moving
        }
        moving.makeKeyAndOrderFront(nil)
        DocumentTabs.hideNativeTabBar(host)
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
    }

    /// Opens dropped files as Tabs of this window, before Tab `slot`.
    func openFiles(_ urls: [URL], at slot: Int?) {
        guard let window else { return }
        DocumentTabs.open(urls, in: window.tabGroup?.selectedWindow ?? window, at: slot)
    }

    func slot(atStripX x: CGFloat) -> Int {
        guard tabWidth > 0 else { return items.count }
        return min(max(0, Int(((x - stripInset) / tabWidth).rounded())), items.count)
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

#if os(macOS)
import AppKit

/// Puts every new document window, new or opened from a file, into the front
/// window's tab group. DocumentGroup otherwise opens a separate window even when
/// the system tabbing mode is "always".
@MainActor
enum DocumentTabs {
    private static var host: NSWindow?
    /// The next new document window stays a window of its own (launch, restore).
    private static var wantsNewWindow = false
    /// While a tab is being dragged out, the new window must stay a window.
    private static var suppress = false
    private static var insertAt: Int?
    /// Windows whose place (a tab of some window, or a window of their own) is decided.
    private static let placed = NSHashTable<NSWindow>.weakObjects()
    /// Windows we have already brought on screen. Ordering a closed window front
    /// again puts its tab straight back.
    private static let shown = NSHashTable<NSWindow>.weakObjects()

    static func install() {
        suppressOpenPanelUntil = Date().addingTimeInterval(2)
        UserDefaults.standard.set("always", forKey: "AppleWindowTabbingMode")
        NSWindow.allowsAutomaticWindowTabbing = true
        // Windows AppKit restores keep the windows they had; only later ones are tabbed.
        restoring = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishRestoringWindowsNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in finishRestoring() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                if let panel = window as? NSOpenPanel, Date() < suppressOpenPanelUntil {
                    panel.cancel(nil)
                    return
                }
                adoptIfNeeded(window)
            }
        }
    }

    private static var suppressOpenPanelUntil = Date.distantPast
    private static var restoring = false

    /// Ends the launch window-restoration phase: every document window that exists
    /// now has its place.
    static func finishRestoring() {
        guard restoring else { return }
        restoring = false
        for window in NSApp.windows where window.tabbingIdentifier == "SkinnyDipDocument" || window.windowController?.document is NSDocument {
            placed.add(window)
        }
    }

    static func configure(_ window: NSWindow) {
        if window.tabbingMode != .preferred { window.tabbingMode = .preferred }
        if window.tabbingIdentifier != "SkinnyDipDocument" { window.tabbingIdentifier = "SkinnyDipDocument" }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
        if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
        if window.isOpaque { window.isOpaque = false }
        if window.backgroundColor != .clear { window.backgroundColor = .clear }
        // An empty compact unified toolbar makes AppKit's title bar 38 pt, the height of
        // ours, so the traffic lights sit centred on the Tab strip and stay there
        // through resizing and full screen.
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "SkinnyDipShell")
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
        if window.toolbarStyle != .unifiedCompact { window.toolbarStyle = .unifiedCompact }
        hideNativeTabBar(window)
        // Remember a window only after it has actually appeared. A later update
        // must not order it front again, or a closed tab comes back.
        guard !shown.contains(window), !window.isMiniaturized else { return }
        if !window.isVisible {
            bringOnScreen(window)
            window.makeKeyAndOrderFront(nil)
        }
        if window.isVisible {
            shown.add(window)
        }
    }

    private static func bringOnScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let shown = visible.intersection(window.frame)
        guard shown.width < 80 || shown.height < 80 else { return }
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width - 40)
        frame.size.height = min(frame.height, visible.height - 40)
        frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.midY - frame.height / 2)
        window.setFrame(frame, display: true)
    }

    /// AppKit puts the system tab bar back as soon as a window has two tabs.
    /// The strip in the title bar is the only tab UI (ADR-0005).
    static func frontDocumentWindow() -> NSWindow? {
        let candidates = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.windows
        return candidates.compactMap { $0 }.first {
            $0.tabbingIdentifier == "SkinnyDipDocument" && $0.isVisible
        }
    }

    /// The selected Tab of the front document Window: the target of per-Tab menu commands.
    static func frontDocumentTab() -> NSWindow? {
        guard let window = frontDocumentWindow() else { return nil }
        return window.tabGroup?.selectedWindow ?? window
    }

    static func hideNativeTabBar(_ window: NSWindow) {
        guard let group = window.tabGroup, group.windows.count > 1 else { return }
        guard let border = window.contentView?.superview else { return }
        hideSystemTabBar(in: border, skipping: window.contentView)
    }

    /// The system tab strip is an `NSTitlebarAccessoryContainerView` inside the title bar.
    /// Hiding it leaves the traffic lights and our own strip.
    private static func hideSystemTabBar(in view: NSView, skipping content: NSView?) {
        guard view !== content else { return }
        let name = NSStringFromClass(type(of: view))
        if name.contains("TitlebarAccessory") {
            view.isHidden = true
            if let parent = view.superview, NSStringFromClass(type(of: parent)) == "NSView" {
                parent.isHidden = true
            }
        }
        for child in view.subviews {
            hideSystemTabBar(in: child, skipping: content)
        }
    }

    /// `host` nil opens a new window. Otherwise the new document becomes a tab of `host`.
    static func newDocument(in host: NSWindow?, at index: Int? = nil) {
        self.host = host
        wantsNewWindow = host == nil
        insertAt = index
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        NSDocumentController.shared.newDocument(nil)
        for window in NSApp.windows where !before.contains(ObjectIdentifier(window)) {
            adoptIfNeeded(window)
        }
        wantsNewWindow = false
        DispatchQueue.main.async {
            NSApp.windows.filter { $0.tabbingIdentifier == "SkinnyDipDocument" }.forEach(hideNativeTabBar)
        }
    }

    static func beginDetachedWindow() {
        suppress = true
        host = nil
        insertAt = nil
    }

    static func endDetachedWindow() {
        suppress = false
    }

    /// Opens files as Tabs of `host`, starting at `index`, one after another so
    /// each lands in order. A file that is already open just selects its Tab.
    static func open(_ urls: [URL], in host: NSWindow, at index: Int?) {
        guard let url = urls.first else { return }
        self.host = host
        insertAt = index
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
            Task { @MainActor in
                // Its window may not have become key yet; place it now, while `host` is pending.
                for controller in document?.windowControllers ?? [] {
                    if let window = controller.window { adoptIfNeeded(window) }
                }
                // Nothing new was adopted, so the pending host must not catch a later window.
                if self.host === host {
                    self.host = nil
                    insertAt = nil
                }
                open(Array(urls.dropFirst()), in: host, at: index.map { $0 + 1 })
            }
        }
    }

    /// The window a new document joins when nobody named one: the frontmost
    /// document window outside `window`'s own tab group.
    private static func frontHost(excluding window: NSWindow) -> NSWindow? {
        let own = window.tabGroup?.windows ?? [window]
        return NSApp.orderedWindows.first { candidate in
            candidate.tabbingIdentifier == "SkinnyDipDocument"
                && candidate.isVisible
                && !candidate.isMiniaturized
                && candidate.windowController?.document is NSDocument
                && !own.contains { $0 === candidate }
        }
    }

    /// Configures a document window and, the first time, decides its place.
    static func adoptIfNeeded(_ window: NSWindow) {
        guard window.windowController?.document is NSDocument else { return }
        configure(window)
        guard !placed.contains(window) else { return }
        placed.add(window)
        guard !suppress, !wantsNewWindow, !restoring || host != nil else { return }
        guard let host = host ?? frontHost(excluding: window), host !== window else { return }
        let index = insertAt
        self.host = nil
        insertAt = nil
        let alreadyTabbed = host.tabGroup?.windows.contains(where: { $0 === window }) == true
        // A file opened over an untouched empty Tab takes its place (ADR-0007: there is
        // nothing in it to lose).
        let replaced = (window.windowController?.document as? NSDocument)?.fileURL != nil
            ? (host.tabGroup?.selectedWindow ?? host)
            : nil
        if !alreadyTabbed {
            host.addTabbedWindow(window, ordered: .above)
        }
        if let replaced, replaced !== window, ScratchSession.shared.isBlank(replaced) {
            replaced.closeDocumentWindow()
        }
        if let index, let group = window.tabGroup {
            let from = group.windows.firstIndex(where: { $0 === window }) ?? 0
            let destination = min(max(0, index), max(group.windows.count - 1, 0))
            if from != destination {
                group.removeWindow(window)
                group.insertWindow(window, at: min(destination, group.windows.count))
            }
            group.selectedWindow = window
        }
        window.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .tabsDidChange, object: nil)
    }
}
#endif

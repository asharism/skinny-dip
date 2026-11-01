#if os(macOS)
import AppKit

/// Writing Tools menu workarounds for WKWebView (see MarkEdit `AppWritingTools.swift`).
@MainActor
enum AppWritingTools {
    /// WebKit private entry point (`sel_getUid("_showWritingTools")`, no trailing colon).
    static let webKitAction = Selector(("_showWritingTools"))

    private static let skinyDipWritingToolsID = NSUserInterfaceItemIdentifier("skinnyDipWritingTools")

    /// Context menu: the system Writing Tools submenu (Proofread, Rewrite, …).
    /// Falls back to WebKit's `_showWritingTools` when that submenu is unavailable.
    static func ensureWritingTools(menu: NSMenu, target: EditorWebView) {
        if let existing = menu.items.first(where: { $0.identifier == skinyDipWritingToolsID }) {
            if let submenu = NSMenuItem.systemWritingToolsItem?.submenu?.copy() as? NSMenu {
                existing.submenu = submenu
                existing.action = nil
            }
            return
        }

        let item = NSMenuItem(title: "Writing Tools", action: nil, keyEquivalent: "")
        item.identifier = skinyDipWritingToolsID
        if let systemItem = NSMenuItem.systemWritingToolsItem {
            item.title = systemItem.title
            item.submenu = systemItem.submenu?.copy() as? NSMenu
        } else {
            item.action = webKitAction
            item.target = target
        }

        let index: Int = {
            if let spelling = menu.items.first(where: { $0.identifier == .spellingMenu }) {
                return menu.index(of: spelling)
            }
            return 0
        }()

        menu.items.insert(item, at: index)
        menu.items.insert(.separator(), at: index + 1)
    }

    static func installMainMenuWritingTools() {
        guard let editMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu else { return }
        syncSystemWritingToolsSubmenu(in: editMenu)
    }

    /// Edit menu: mirror the system Writing Tools submenu (Proofread, Rewrite, …).
    static func syncSystemWritingToolsSubmenu(in editMenu: NSMenu) {
        guard let systemItem = NSMenuItem.systemWritingToolsItem else { return }

        let item: NSMenuItem
        if let existing = editMenu.items.first(where: { $0.identifier == skinyDipWritingToolsID }) {
            item = existing
        } else {
            item = NSMenuItem(title: systemItem.title, action: nil, keyEquivalent: "")
            item.identifier = skinyDipWritingToolsID
            let index: Int = {
                if let spelling = editMenu.items.first(where: { $0.identifier == .spellingMenu }) {
                    return editMenu.index(of: spelling)
                }
                return 0
            }()
            editMenu.insertItem(item, at: index)
            editMenu.insertItem(.separator(), at: index + 1)
        }

        item.title = systemItem.title
        item.submenu = systemItem.submenu?.copy() as? NSMenu
        item.isHidden = false
    }
}

private extension NSMenuItem {
    /// Same SPI MarkEdit uses (`standardWritingToolsMenuItem`).
    static var systemWritingToolsItem: NSMenuItem? {
        let selector = Selector(("standardWritingToolsMenuItem"))
        guard NSMenuItem.responds(to: selector) else { return nil }
        return NSMenuItem.perform(selector)?.takeUnretainedValue() as? NSMenuItem
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let spellingMenu = Self("WKMenuItemIdentifierSpellingMenu")
}
#endif

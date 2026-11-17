#if os(macOS)
import AppKit

/// Mirrors the system Writing Tools submenu into the Edit menu (see MarkEdit `AppWritingTools.swift`).
@MainActor
enum AppWritingTools {
    private static let skinyDipWritingToolsID = NSUserInterfaceItemIdentifier("skinnyDipWritingTools")

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

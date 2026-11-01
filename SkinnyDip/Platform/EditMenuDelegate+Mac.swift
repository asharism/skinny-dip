#if os(macOS)
import AppKit

/// Keeps Writing Tools and Spelling items on the Edit menu wired for the key window's editor web view.
@MainActor
final class EditMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = EditMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == NSApp.mainMenu?.item(withTitle: "Edit")?.submenu else { return }
        AppWritingTools.installMainMenuWritingTools()
        AppWritingTools.syncSystemWritingToolsSubmenu(in: menu)
    }
}
#endif

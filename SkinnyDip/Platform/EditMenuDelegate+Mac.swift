#if os(macOS)
import AppKit

/// Keeps the Writing Tools item on the Edit menu in step with the system's submenu.
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

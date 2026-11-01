import SwiftUI
#if os(macOS)
import AppKit

/// Opens an untitled document on launch when nothing is restored; skipped for Finder-open and state restoration.
private final class SkinnyDipAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        EditorTextCheckerDefaults.enable()
        object_setClass(NSApp, SkinnyDipApplication.self)
        if let editMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu {
            editMenu.delegate = EditMenuDelegate.shared
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        EditorSpellCheck.warmUp()
        AppWritingTools.installMainMenuWritingTools()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppWritingTools.installMainMenuWritingTools()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
    }
}
#endif

@main
struct SkinnyDipApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SkinnyDipAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        #if os(macOS)
        .defaultLaunchBehavior(.presented)
        .commands { CopyCommands() }
        #endif

        #if os(macOS)
        Settings { SettingsView() }
            .defaultLaunchBehavior(.suppressed)
        #endif
    }
}

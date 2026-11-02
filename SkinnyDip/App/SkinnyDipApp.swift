import SwiftUI
import MarkdownCore
#if os(macOS)
import AppKit

/// Opens an untitled document on launch when nothing is restored; skipped for Finder-open and state restoration.
private final class SkinnyDipAppDelegate: NSObject, NSApplicationDelegate {
    private var didFinishLaunch = false

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        guard !didFinishLaunch else { return false }
        return ScratchSession.shared.shouldOpenUntitled
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ScratchSession.shared.terminate()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        DocumentTabs.install()
        UserDefaults.standard.register(defaults: [
            "AppleWindowTabbingMode": "always",
            "uiZoom": 1.0,
            "scrollSync": true,
            "themeMode": ThemeSelection.matchSystem,
            "themeFixed": ThemeSelection.defaultLight,
            "themeLight": ThemeSelection.defaultLight,
            "themeDark": ThemeSelection.defaultDark,
            "paneOrientation": "sideBySide",
        ])
        NSWindow.allowsAutomaticWindowTabbing = true
        ScratchSession.shared.installCloseHook()
        ScratchSession.shared.prepareLaunch()
        EditorTextCheckerDefaults.enable()
        object_setClass(NSApp, SkinnyDipApplication.self)
        if let editMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu {
            editMenu.delegate = EditMenuDelegate.shared
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.charactersIgnoringModifiers?.lowercased()
            if flags == .command, characters == "=" {
                let next = ZoomLevel(UserDefaults.standard.object(forKey: "uiZoom") as? Double ?? 1).next()
                UserDefaults.standard.set(next.value, forKey: "uiZoom")
                return nil
            }
            // The editor web view claims ⌘W and never closes the tab.
            if flags == .command, characters == "w",
               let window = NSApp.keyWindow, !(window is NSPanel) {
                window.closeDocumentWindow()
                return nil
            }
            return event
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ScratchSession.shared.openRestoredDocuments()
        let hasDocument = NSApp.windows.contains { $0.windowController?.document is NSDocument }
        if !hasDocument {
            for case let panel as NSOpenPanel in NSApp.windows {
                panel.cancel(nil)
            }
            DocumentTabs.newDocument(in: nil)
        }
        EditorSpellCheck.warmUp()
        AppWritingTools.installMainMenuWritingTools()
        didFinishLaunch = true
        _ = AppUpdater.shared
        #if DEBUG
        DebugSnapshot.installIfRequested()
        #endif
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

    #if os(macOS)
    @StateObject private var themes = ThemeStore()
    @AppStorage("uiZoom") private var uiZoom = 1.0
    @AppStorage("themeMode") private var themeMode = ThemeSelection.matchSystem
    @AppStorage("themeFixed") private var themeFixed = ThemeSelection.defaultLight
    #endif

    var body: some Scene {
        #if os(macOS)
        DocumentGroup(newDocument: ScratchSession.makeDocumentForGroup()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .environmentObject(themes)
                .environment(\.metrics, Metrics(zoom: uiZoom))
                .preferredColorScheme(preferredScheme)
        }
        .defaultLaunchBehavior(.presented)
        // Room for two Cards and the full footer at 100% Zoom.
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CopyCommands()
            TabCommands()
            DocumentCommands()
            ViewCommands()
            UpdateCommands()
        }
        #else
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(themes)
                .environment(\.metrics, Metrics(zoom: uiZoom))
        }
        .defaultLaunchBehavior(.suppressed)
        #endif
    }

    #if os(macOS)
    private var preferredScheme: ColorScheme? {
        guard themeMode == ThemeSelection.fixed else { return nil }
        return themes.file(id: themeFixed)?.appearance == .dark ? .dark : .light
    }
    #endif
}

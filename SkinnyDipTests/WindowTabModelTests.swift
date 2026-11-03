#if os(macOS)
import AppKit
import Testing
@testable import SkinnyDip

/// Real windows in a real tab group, so AppKit's own tab-bar behaviour is in play.
@MainActor
struct WindowTabModelTests {
    /// Hiding the system tab bar once made AppKit report it visible again from inside
    /// `toggleTabBar`, which re-triggered the hide forever: 100% CPU, and clicks on
    /// Tabs and the Preview eaten, from the moment a window held two Tabs.
    @Test func twoTabsGoQuietOnceTheSystemTabBarIsHidden() async throws {
        let first = Self.window()
        let second = Self.window()
        defer {
            second.close()
            first.close()
        }
        first.makeKeyAndOrderFront(nil)
        first.addTabbedWindow(second, ordered: .above)
        try #require(first.tabGroup?.windows.count == 2)

        let models = [WindowTabModel(), WindowTabModel()]
        models[0].attach(first)
        models[1].attach(second)

        // Let the attach-time changes settle, then the run loop should have nothing to do.
        try await Task.sleep(for: .milliseconds(300))
        let settled = models.map(\.refreshCount)
        try await Task.sleep(for: .milliseconds(500))

        #expect(models.map(\.refreshCount) == settled)
        #expect(models[0].items.count == 2)
    }

    private static func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        DocumentTabs.configure(window)
        return window
    }
}
#endif

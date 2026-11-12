#if os(macOS)
import AppKit

/// Switching Editor Backend relaunches Skinny (ADR-0010): the backend is read
/// once at launch, so the new choice takes effect in a fresh instance.
@MainActor
enum EditorBackendSwitch {
    static let warning = "Switching editors relaunches Skinny. Your documents and Tabs come back, but undo history for open documents is cleared."
    static let fallback = "Quit and reopen Skinny to switch editors."

    /// Stores the choice, writes every document to disk, starts a new instance
    /// and quits this one. Calls `failed` if macOS refuses to start the new
    /// instance; the choice is still stored and applies at the next launch.
    static func relaunch(
        to kind: EditorBackendKind,
        defaults: UserDefaults = .standard,
        failed: @escaping @MainActor () -> Void
    ) {
        kind.store(in: defaults)
        defaults.synchronize()
        // Save before the new instance starts: it restores from disk at launch.
        ScratchSession.shared.saveAll()
        ScratchSession.shared.saveUserFiles()

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor in
                if let error {
                    #if DEBUG
                    fputs("[SkinnyDip] relaunch failed: \(error)\n", stderr)
                    #endif
                    failed()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
#endif

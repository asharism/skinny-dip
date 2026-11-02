#if os(macOS)
import Combine
import Sparkle
import SwiftUI

/// Sparkle auto-update from GitHub Releases (ADR-0009). The feed URL, EdDSA
/// public key and daily automatic checks are Info.plist keys in `project.yml`.
/// Debug builds never start the updater, so a dev build isn't offered a release.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController

    private init() {
        #if DEBUG
        let start = false
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: start,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

/// "Check for Updates…" in the app menu, under About.
struct UpdateCommands: Commands {
    @ObservedObject private var updater = AppUpdater.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.canCheckForUpdates)
        }
    }
}
#endif

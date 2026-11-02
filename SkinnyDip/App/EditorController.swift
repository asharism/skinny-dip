#if os(macOS)
import Foundation

struct EditorViewport: Equatable {
    var topLine: Int
    var fraction: Double
}

/// Per-document bridge to the CodeMirror web view. The shell asks it for undo
/// history and reads the cursor and viewport the editor already reports.
@MainActor
final class EditorController: ObservableObject {
    @Published var cursorUTF16 = 0
    @Published var viewport = EditorViewport(topLine: 1, fraction: 0)
    var exportState: (() async -> String?)?
    var importState: ((String) async -> Void)?
    var pendingHistory: String?
    private var latestHistory: String?

    func noteHistory(_ json: String?) {
        latestHistory = json
    }

    /// Runs the async export on the main run loop. Close and quit need the
    /// history before AppKit decides whether to prompt.
    func exportHistoryBlocking() -> String? {
        guard let exportState else { return latestHistory }
        var value: String?
        var finished = false
        let task = Task { @MainActor in
            value = await exportState()
            finished = true
        }
        let deadline = Date().addingTimeInterval(0.4)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .common, before: Date(timeIntervalSinceNow: 0.02))
        }
        if !finished { task.cancel() }
        if let value { latestHistory = value }
        return finished ? value : latestHistory
    }
}
#endif

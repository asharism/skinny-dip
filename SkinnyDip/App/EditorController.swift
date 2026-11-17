#if os(macOS)
import Foundation

struct EditorViewport: Equatable {
    var topLine: Int
    var fraction: Double
}

/// Per-document link to the editor: the shell reads the cursor and viewport
/// the editor reports.
@MainActor
final class EditorController: ObservableObject {
    @Published var cursorUTF16 = 0
    @Published var viewport = EditorViewport(topLine: 1, fraction: 0)
    #if DEBUG
    /// Soak harness (#62): the editor calls this with every text change it reports.
    var debugTextObserver: ((String) -> Void)?
    #endif
}
#endif

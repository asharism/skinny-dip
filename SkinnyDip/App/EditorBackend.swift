import Foundation
import MarkdownCore

/// Which Editor Backend runs the Editor Card (ADR-0010). Picked in Settings ›
/// Advanced and read once at launch: the app never switches while running.
/// Native won the trial (ADR-0010 Outcome); CodeMirror is frozen legacy until 0.3.0.
enum EditorBackendKind: String, CaseIterable, Sendable {
    case native
    case codeMirror

    static let defaultsKey = "editorBackend"

    /// The backend for this run, fixed at first use.
    static let current: EditorBackendKind = stored(in: .standard).availableOrDefault

    /// A missing or unknown value means native.
    static func stored(in defaults: UserDefaults) -> EditorBackendKind {
        defaults.string(forKey: defaultsKey).flatMap(EditorBackendKind.init(rawValue:)) ?? .native
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    var title: String {
        switch self {
        case .native: "Native"
        case .codeMirror: "CodeMirror (legacy)"
        }
    }

    /// Every backend can be picked. Kept so a backend can be listed before it lands.
    var isAvailable: Bool { true }

    private var availableOrDefault: EditorBackendKind { isAvailable ? self : .native }
}

/// Scratch Document undo history carries the tag of the backend that wrote it.
/// History from the other backend is dropped and only the text comes back.
enum ScratchHistory {
    static func restorable(
        forText text: String,
        storedHistoryJSON: String?,
        storedBackend: String?,
        current: EditorBackendKind
    ) -> String? {
        // History saved before the tag existed is CodeMirror's; an unknown tag matches nothing.
        let writer: EditorBackendKind? = if let storedBackend {
            EditorBackendKind(rawValue: storedBackend)
        } else {
            .codeMirror
        }
        guard writer == current else { return nil }
        return ScratchRestore.history(forText: text, storedHistoryJSON: storedHistoryJSON)
    }

    static func tag(for history: String?, backend: EditorBackendKind) -> String? {
        history == nil ? nil : backend.rawValue
    }
}

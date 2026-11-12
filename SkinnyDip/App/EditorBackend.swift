import Foundation
import MarkdownCore

/// Which Editor Backend runs the Editor Card (ADR-0010). Picked in Settings ›
/// Advanced and read once at launch: the app never switches while running.
enum EditorBackendKind: String, CaseIterable, Sendable {
    case codeMirror
    case native

    static let defaultsKey = "editorBackend"

    /// The backend for this run, fixed at first use.
    static let current: EditorBackendKind = stored(in: .standard).availableOrDefault

    /// A missing or unknown value means CodeMirror.
    static func stored(in defaults: UserDefaults) -> EditorBackendKind {
        defaults.string(forKey: defaultsKey).flatMap(EditorBackendKind.init(rawValue:)) ?? .codeMirror
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }

    var title: String {
        switch self {
        case .codeMirror: "CodeMirror"
        case .native: "Native (NSTextView)"
        }
    }

    /// Native is listed but disabled until its backend lands (#64).
    var isAvailable: Bool {
        switch self {
        case .codeMirror: true
        case .native: false
        }
    }

    private var availableOrDefault: EditorBackendKind { isAvailable ? self : .codeMirror }
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

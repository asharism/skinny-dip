#if os(macOS)
import SwiftUI

/// The Editor Card's content: the Editor Backend chosen at launch (ADR-0010).
/// Takes what every backend takes, so `ContentView` never names one.
struct EditorHost: View {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    @Binding var hasEditorSelection: Bool
    var documentID: UUID
    var themeVars: [String: String]
    var controller: EditorController
    var backend: EditorBackendKind = .current

    var body: some View {
        switch backend {
        case .codeMirror:
            EditorView(
                text: $text,
                selection: $selection,
                canUndo: $canUndo,
                canRedo: $canRedo,
                hasEditorSelection: $hasEditorSelection,
                documentID: documentID,
                themeVars: themeVars,
                controller: controller
            )
        case .native:
            NativeEditorView(
                text: $text,
                selection: $selection,
                canUndo: $canUndo,
                canRedo: $canRedo,
                hasEditorSelection: $hasEditorSelection,
                documentID: documentID,
                themeVars: themeVars,
                controller: controller
            )
        }
    }
}
#endif

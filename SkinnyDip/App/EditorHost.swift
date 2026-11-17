#if os(macOS)
import SwiftUI

/// The Editor Card's content: the native `NSTextView` editor (ADR-0010).
/// Keeps `ContentView` free of the editor's own settings.
struct EditorHost: View {
    @AppStorage(EditorSettings.showsLineNumbers) private var showsLineNumbers = true
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    @Binding var hasEditorSelection: Bool
    var documentID: UUID
    var themeVars: [String: String]
    var controller: EditorController

    var body: some View {
        NativeEditorView(
            text: $text,
            selection: $selection,
            canUndo: $canUndo,
            canRedo: $canRedo,
            hasEditorSelection: $hasEditorSelection,
            documentID: documentID,
            themeVars: themeVars,
            controller: controller,
            showsLineNumbers: showsLineNumbers
        )
    }
}

/// Editor settings stored in `UserDefaults`.
enum EditorSettings {
    /// View › Show Line Numbers (#76). On by default.
    static let showsLineNumbers = "showsLineNumbers"
}
#endif

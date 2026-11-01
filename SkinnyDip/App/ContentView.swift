import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    #if os(macOS)
    @State private var selection: Range<String.Index>?
    #else
    @State private var textSelection: TextSelection?
    #endif

    var body: some View {
        #if os(macOS)
        EditorView(text: $document.source, selection: $selection)
            .focusedSceneValue(\.copySource, CopySource(
                markdown: document.source,
                selection: selection
            ))
        #else
        TextEditor(text: $document.source, selection: $textSelection)
            .font(.body.monospaced())
            .focusedSceneValue(\.copySource, CopySource(
                markdown: document.source,
                selection: textSelection?.range(in: document.source)
            ))
        #endif
    }
}

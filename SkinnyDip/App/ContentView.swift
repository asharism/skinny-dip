import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @State private var selection: TextSelection?

    var body: some View {
        // Placeholder until the editor spike (issue #1) picks the real editor.
        TextEditor(text: $document.source, selection: $selection)
            .font(.body.monospaced())
            .focusedSceneValue(\.copySource, CopySource(
                markdown: document.source,
                selection: selection?.range(in: document.source)
            ))
    }
}

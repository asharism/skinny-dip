import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument

    var body: some View {
        // Placeholder until the editor spike (issue #1) picks the real editor.
        TextEditor(text: $document.source)
            .font(.body.monospaced())
    }
}

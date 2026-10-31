import SwiftUI
#if os(macOS)
import MarkdownCore
#endif

struct ContentView: View {
    @Binding var document: MarkdownDocument
    #if os(macOS)
    @State private var selection: Range<String.Index>?
    @State private var canUndo = false
    @State private var canRedo = false
    @StateObject private var previewState = DocumentPreviewState()
    @AppStorage("showPreview") private var showPreview = true
    @AppStorage("previewLeadingFraction") private var previewLeadingFraction: Double = 0.5
    @AppStorage(RenderSettings.demotesHeadings) private var demotesHeadings = RenderOptions.default.demotesHeadings
    @AppStorage(RenderSettings.bordersTables) private var bordersTables = RenderOptions.default.bordersTables
    @AppStorage(RenderSettings.newlinesAsBreaks) private var newlinesAsBreaks = RenderOptions.default.newlinesAsBreaks
    #else
    @State private var textSelection: TextSelection?
    #endif

    var body: some View {
        #if os(macOS)
        Group {
            if showPreview {
                SplitPane(leadingFraction: $previewLeadingFraction) {
                    editorPane
                } trailing: {
                    PreviewView(html: previewState.html, markdown: document.source)
                }
            } else {
                editorPane
            }
        }
        .onAppear { refreshPreview() }
        .onChange(of: document.source) { refreshPreview() }
        .onChange(of: demotesHeadings) { refreshPreview() }
        .onChange(of: bordersTables) { refreshPreview() }
        .onChange(of: newlinesAsBreaks) { refreshPreview() }
        .onReceive(NotificationCenter.default.publisher(for: .togglePreview)) { _ in
            showPreview.toggle()
        }
        #else
        TextEditor(text: $document.source, selection: $textSelection)
            .font(.body.monospaced())
            .focusedSceneValue(\.copySource, CopySource(
                markdown: document.source,
                selection: textSelection?.range(in: document.source)
            ))
        #endif
    }

    #if os(macOS)
    private var editorPane: some View {
        EditorView(
            text: $document.source,
            selection: $selection,
            canUndo: $canUndo,
            canRedo: $canRedo
        )
        .focusedSceneValue(\.copySource, CopySource(
            markdown: document.source,
            selection: selection
        ))
        .focusedSceneValue(\.editorHistoryMenuState, EditorHistoryMenuState(canUndo: canUndo, canRedo: canRedo))
    }

    private func refreshPreview() {
        previewState.update(
            source: document.source,
            options: RenderOptions(
                demotesHeadings: demotesHeadings,
                bordersTables: bordersTables,
                newlinesAsBreaks: newlinesAsBreaks
            )
        )
    }
    #endif
}

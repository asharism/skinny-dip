import SwiftUI
#if os(macOS)
import AppKit
import MarkdownCore
#endif

struct ContentView: View {
    @Binding var document: MarkdownDocument
    #if os(macOS)
    @State private var selection: Range<String.Index>?
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var hasEditorSelection = false
    @State private var canPasteFromPasteboard = NSPasteboard.general.canPasteFromPasteboard
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            canRedo: $canRedo,
            hasEditorSelection: $hasEditorSelection
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusedSceneValue(\.copySource, CopySource(
            markdown: document.source,
            selection: selection
        ))
        .focusedSceneValue(\.editorHistoryMenuState, EditorHistoryMenuState(canUndo: canUndo, canRedo: canRedo))
        .focusedSceneValue(\.editorPasteboardMenuState, editorPasteboardMenuState)
        .onAppear { refreshPasteboardMenuState() }
        .onChange(of: hasEditorSelection) { refreshPasteboardMenuState() }
        .onChange(of: document.source) { refreshPasteboardMenuState() }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuWillOpen)) { _ in
            refreshPasteboardMenuState()
        }
    }

    private var editorPasteboardMenuState: EditorPasteboardMenuState {
        EditorPasteboardMenuState(
            canCut: hasEditorSelection,
            canCopy: hasEditorSelection || !document.source.isEmpty,
            canPaste: canPasteFromPasteboard
        )
    }

    private func refreshPasteboardMenuState() {
        canPasteFromPasteboard = NSPasteboard.general.canPasteFromPasteboard
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

#if os(macOS)
extension Notification.Name {
    static let editorMenuWillOpen = Notification.Name("skinnyDipEditorMenuWillOpen")
}
#endif

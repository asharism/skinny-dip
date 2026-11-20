#if os(macOS)
import Combine
import MarkdownCore

@MainActor
final class DocumentPreviewState: ObservableObject {
    @Published private(set) var html = ""
    /// The top-level block lines of the source `html` came from.
    @Published private(set) var blocks = PreviewBlocks.empty
    private let parser = MarkdownParser()

    func update(source: String, options: RenderOptions) {
        Task {
            await parser.render(source: source, options: options) { [weak self] render in
                self?.blocks = render.blocks
                self?.html = render.html
            }
        }
    }
}
#endif

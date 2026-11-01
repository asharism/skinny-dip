#if os(macOS)
import Combine
import MarkdownCore

@MainActor
final class DocumentPreviewState: ObservableObject {
    @Published private(set) var html = ""
    private let parser = MarkdownParser()

    func update(source: String, options: RenderOptions) {
        Task {
            await parser.update(source: source, options: options) { [weak self] html in
                self?.html = html
            }
        }
    }
}
#endif

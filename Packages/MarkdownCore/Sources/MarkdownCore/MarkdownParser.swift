/// Debounced, off-main rendering for the live Preview (P3).
public actor MarkdownParser {
    public let debounceNanoseconds: UInt64

    private var renderTask: Task<Void, Never>?

    public init(debounceNanoseconds: UInt64 = 200_000_000) {
        self.debounceNanoseconds = debounceNanoseconds
    }

    /// Schedules a render; cancels any in-flight debounce/render from a prior call.
    public func update(
        source: String,
        options: RenderOptions,
        deliver: @escaping @Sendable @MainActor (String) -> Void
    ) {
        render(source: source, options: options) { render in deliver(render.html) }
    }

    /// Like `update`, but also delivers the top-level block lines of the same source.
    public func render(
        source: String,
        options: RenderOptions,
        deliver: @escaping @Sendable @MainActor (PreviewRender) -> Void
    ) {
        renderTask?.cancel()
        let delay = debounceNanoseconds
        renderTask = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let render = await Task.detached(priority: .userInitiated) {
                PreviewRender(html: PreviewHTML.render(source, options: options), blocks: PreviewBlocks(source: source))
            }.value
            guard !Task.isCancelled else { return }
            await deliver(render)
        }
    }
}

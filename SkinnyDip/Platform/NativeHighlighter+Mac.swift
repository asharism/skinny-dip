#if os(macOS)
import AppKit
import MarkdownCore

/// Colors the native editor's Markdown Source from `highlightSpans` (ADR-0010).
/// Parses off the main thread after a pause in typing, keeps only the latest
/// generation, and sets only the foreground color, directly on the text
/// storage, so it never adds undo steps or marks the document edited. The
/// approach follows Silica's `SyntaxHighlighter` (MIT).
@MainActor
final class NativeHighlighter {
    private weak var textView: NSTextView?
    private var pending: Task<Void, Never>?
    private var generation = 0
    var theme: NativeEditorTheme

    /// Above this many UTF-16 units, the text stays plain.
    static let maxLength = 2_000_000
    /// Up to this size the first pass runs synchronously, so a document opens colored.
    static let synchronousLength = 100_000
    static let editDelay: Duration = .milliseconds(120)

    init(textView: NSTextView, theme: NativeEditorTheme) {
        self.textView = textView
        self.theme = theme
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    /// Opening a document or changing the theme: synchronous for small documents.
    func highlightNow() {
        guard let storage = textView?.textStorage, storage.length <= Self.maxLength else { return }
        if storage.length <= Self.synchronousLength {
            generation += 1
            pending?.cancel()
            apply(highlightSpans(in: storage.string))
        } else {
            schedule(after: .zero)
        }
    }

    func textDidChange() {
        schedule(after: Self.editDelay)
    }

    private func schedule(after delay: Duration) {
        generation += 1
        let expected = generation
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled, let text = self?.snapshot() else { return }
            let spans = await Task.detached(priority: .userInitiated) {
                highlightSpans(in: text)
            }.value
            guard !Task.isCancelled, let self, expected == self.generation else { return }
            self.apply(spans)
        }
    }

    private func snapshot() -> String? {
        guard let storage = textView?.textStorage, storage.length <= Self.maxLength else { return nil }
        return String(storage.string)
    }

    private func apply(_ spans: [HighlightSpan]) {
        guard let textView, let storage = textView.textStorage else { return }
        // Recoloring under IME composition would disturb the marked text.
        if textView.hasMarkedText() {
            schedule(after: Self.editDelay)
            return
        }
        let length = storage.length
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: theme.foreground, range: NSRange(location: 0, length: length))
        for span in spans where NSMaxRange(span.range) <= length {
            storage.addAttribute(.foregroundColor, value: theme.color(for: span.role), range: span.range)
        }
        storage.endEditing()
    }
}
#endif

#if os(macOS)
import AppKit
import MarkdownCore

/// Colors the native editor's Markdown Source from `highlightSpans` (ADR-0010).
/// Parses off the main thread after a pause in typing, keeps only the latest
/// generation, and sets only the foreground color and the font's bold and
/// italic traits, directly on the text storage, so it never adds undo steps or
/// marks the document edited. The approach follows Silica's
/// `SyntaxHighlighter` (MIT).
///
/// It sets an attribute only where it differs from what the storage already
/// has. TextKit 2 throws away layout for every range whose attributes change,
/// and a whole-document pass after each pause in typing left the visible
/// fragments at estimated positions in long files: the bottom of the text,
/// the caret line and the gutter numbers blanked until the next scroll.
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
            let text = storage.string
            apply(highlightRuns(for: highlightSpans(in: text), length: (text as NSString).length))
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
            let runs = await Task.detached(priority: .userInitiated) {
                highlightRuns(for: highlightSpans(in: text), length: (text as NSString).length)
            }.value
            guard !Task.isCancelled, let self, expected == self.generation else { return }
            self.apply(runs)
        }
    }

    private func snapshot() -> String? {
        guard let storage = textView?.textStorage, storage.length <= Self.maxLength else { return nil }
        return String(storage.string)
    }

    private func apply(_ runs: [HighlightRun]) {
        guard let textView, let storage = textView.textStorage else { return }
        // Recoloring under IME composition would disturb the marked text.
        if textView.hasMarkedText() {
            schedule(after: Self.editDelay)
            return
        }
        let length = storage.length
        guard runs.last.map({ NSMaxRange($0.range) }) ?? 0 == length else {
            // The text changed since the parse; the next pass catches up.
            schedule(after: Self.editDelay)
            return
        }
        var editing = false
        func set(_ key: NSAttributedString.Key, _ value: Any, _ range: NSRange) {
            if !editing { storage.beginEditing(); editing = true }
            storage.addAttribute(key, value: value, range: range)
        }
        let fonts = [false, true].flatMap { bold in [false, true].map { theme.font(bold: bold, italic: $0) } }
        for run in runs {
            let color = run.color.map { theme.color(for: $0) } ?? theme.foreground
            let font = fonts[(run.bold ? 2 : 0) + (run.italic ? 1 : 0)]
            storage.enumerateAttribute(.foregroundColor, in: run.range) { value, range, _ in
                if (value as? NSColor) != color { set(.foregroundColor, color, range) }
            }
            storage.enumerateAttribute(.font, in: run.range) { value, range, _ in
                if (value as? NSFont) != font { set(.font, font, range) }
            }
        }
        if editing { storage.endEditing() }
    }
}
#endif

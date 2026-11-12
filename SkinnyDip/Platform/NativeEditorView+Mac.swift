#if os(macOS)
import AppKit
import MarkdownCore
import SwiftUI

/// The native Editor Backend (ADR-0010): `NSTextView` on TextKit 2, with the
/// same inputs as the CodeMirror `EditorView`. The scroll view and text view
/// are built by hand because `NSTextView.scrollableTextView()` returns a
/// TextKit 1 view (Silica's `TextController`, MIT).
struct NativeEditorView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: Range<String.Index>?
    @Binding var canUndo: Bool
    @Binding var canRedo: Bool
    @Binding var hasEditorSelection: Bool
    var documentID: UUID
    var themeVars: [String: String]
    var controller: EditorController

    static let editDebounceNanoseconds: UInt64 = 200_000_000
    static let placeholder = "Start typing Markdown. ⌘V turns rich text into Markdown."

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(from: self)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private(set) var parent: NativeEditorView
        private(set) weak var textView: NativeEditorTextView?
        private weak var scrollView: NSScrollView?
        private var highlighter: NativeHighlighter?
        private var theme: NativeEditorTheme
        private let undoManager = UndoManager()
        /// The text the binding last saw from us, so an update that carries it is no echo.
        private var lastEditorText: String
        private var isApplyingRemoteEdit = false
        private var isBindingSyncPending = false
        private var debounceTask: Task<Void, Never>?
        private var viewportScheduled = false
        private var lineStarts: [Int]?

        init(parent: NativeEditorView) {
            self.parent = parent
            theme = NativeEditorTheme(vars: parent.themeVars)
            lastEditorText = parent.text
            super.init()
        }

        func makeScrollView() -> NSScrollView {
            let scrollView = NSScrollView()
            let textView = NativeEditorTextView(usingTextLayoutManager: true)
            textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
            textView.minSize = .zero
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
            textView.textContainer?.lineFragmentPadding = 0
            scrollView.documentView = textView
            scrollView.drawsBackground = false
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.scrollerStyle = .overlay

            textView.drawsBackground = false
            textView.isRichText = false
            textView.importsGraphics = false
            textView.allowsUndo = true
            textView.usesFindBar = true
            textView.isIncrementalSearchingEnabled = true
            // The Markdown Source is never rewritten (ADR-0002): no smart quotes,
            // dashes or text replacement. Spell check stays on; autocorrect follows
            // the system setting, as WebKit does for CodeMirror.
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
            textView.isAutomaticDataDetectionEnabled = false
            textView.smartInsertDeleteEnabled = false
            textView.isContinuousSpellCheckingEnabled = true
            textView.isGrammarCheckingEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = NSSpellChecker.isAutomaticSpellingCorrectionEnabled
            textView.writingToolsBehavior = .complete

            textView.editorCoordinator = self
            self.textView = textView
            self.scrollView = scrollView
            applyTheme(to: textView)
            // The opening text is not an edit: no undo step.
            textView.textStorage?.setAttributedString(NSAttributedString(string: parent.text, attributes: theme.baseAttributes))
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.delegate = self

            highlighter = NativeHighlighter(textView: textView, theme: theme)
            highlighter?.highlightNow()

            // Scratch Documents restore text without undo history in this backend (ADR-0010).
            parent.controller.exportState = nil
            parent.controller.importState = nil
            parent.controller.pendingHistory = nil

            let center = NotificationCenter.default
            for name in [Notification.Name.NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
                center.addObserver(self, selector: #selector(undoStateChanged(_:)), name: name, object: undoManager)
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
            center.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
            return scrollView
        }

        func update(from parent: NativeEditorView) {
            self.parent = parent
            let next = NativeEditorTheme(vars: parent.themeVars)
            if next != theme, let textView {
                theme = next
                applyTheme(to: textView)
                restyleAll(textView)
                highlighter?.theme = next
                highlighter?.highlightNow()
            }
            guard let textView, parent.text != lastEditorText, !isBindingSyncPending, !isApplyingRemoteEdit else { return }
            replaceAll(with: parent.text, in: textView)
        }

        func tearDown() {
            debounceTask?.cancel()
            highlighter?.cancel()
            highlighter = nil
            NotificationCenter.default.removeObserver(self)
            textView?.delegate = nil
            textView?.editorCoordinator = nil
        }

        func highlightNow() {
            highlighter?.highlightNow()
        }

        /// An outside change (Scratch restore, a reload): one undoable edit.
        private func replaceAll(with text: String, in textView: NativeEditorTextView) {
            isApplyingRemoteEdit = true
            defer { isApplyingRemoteEdit = false }
            let whole = NSRange(location: 0, length: (textView.string as NSString).length)
            textView.breakUndoCoalescing()
            if textView.shouldChangeText(in: whole, replacementString: text) {
                textView.textStorage?.replaceCharacters(in: whole, with: NSAttributedString(string: text, attributes: theme.baseAttributes))
                textView.didChangeText()
            }
            textView.breakUndoCoalescing()
            lastEditorText = text
            lineStarts = nil
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            highlighter?.highlightNow()
        }

        private func applyTheme(to textView: NSTextView) {
            textView.font = theme.font
            textView.textColor = theme.foreground
            textView.insertionPointColor = theme.cursor
            textView.selectedTextAttributes = [.backgroundColor: theme.selection]
            textView.defaultParagraphStyle = theme.paragraphStyle
            textView.typingAttributes = theme.baseAttributes
            let insets = theme.insets
            textView.textContainerInset = NSSize(width: insets.horizontal, height: insets.top)
            // NSTextView draws `placeholderAttributedString` while it is empty.
            guard textView.responds(to: NSSelectorFromString("setPlaceholderAttributedString:")) else { return }
            textView.setValue(
                NSAttributedString(string: NativeEditorView.placeholder, attributes: [
                    .font: theme.font,
                    .foregroundColor: theme.muted,
                    .paragraphStyle: theme.paragraphStyle,
                ]),
                forKey: "placeholderAttributedString"
            )
        }

        /// Zoom or a theme change: font and line height for every run, colors after.
        /// Attribute-only, straight on the storage, so no undo step.
        private func restyleAll(_ textView: NSTextView) {
            guard let storage = textView.textStorage, storage.length > 0 else { return }
            storage.beginEditing()
            storage.addAttributes(theme.baseAttributes, range: NSRange(location: 0, length: storage.length))
            storage.endEditing()
        }

        // MARK: NSTextViewDelegate

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            lineStarts = nil
            highlighter?.textDidChange()
            let newText = textView.string
            lastEditorText = newText
            #if DEBUG
            parent.controller.debugTextObserver?(newText)
            #endif
            guard !isApplyingRemoteEdit else {
                parent.text = newText
                return
            }
            debounceTask?.cancel()
            isBindingSyncPending = true
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: NativeEditorView.editDebounceNanoseconds)
                guard !Task.isCancelled, let self else { return }
                self.isBindingSyncPending = false
                if self.parent.text != newText {
                    self.parent.text = newText
                }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            let ranges = textView.selectedRanges.map(\.rangeValue)
            let main = ranges.first ?? NSRange(location: 0, length: 0)
            parent.controller.cursorUTF16 = main.location
            let hasSelection = ranges.contains { $0.length > 0 }
            if parent.hasEditorSelection != hasSelection {
                parent.hasEditorSelection = hasSelection
            }
            let markdown = textView.string
            if ranges.count == 1, main.length > 0,
               let range = UTF16Selection.range(in: markdown, from: main.location, to: NSMaxRange(main)) {
                parent.selection = range
            } else if parent.selection != nil {
                parent.selection = nil
            }
        }

        @objc private func undoStateChanged(_ notification: Notification) {
            // AppKit posts these mid-group; read the state once the edit is done.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.canUndo != self.undoManager.canUndo { self.parent.canUndo = self.undoManager.canUndo }
                if self.parent.canRedo != self.undoManager.canRedo { self.parent.canRedo = self.undoManager.canRedo }
            }
        }

        // MARK: Scroll sync (ADR-0006)

        @objc private func boundsChanged(_ notification: Notification) {
            // At most one report per pass of the run loop: scroll events arrive
            // once per frame, so this matches `reportViewport` in editor.js
            // (requestAnimationFrame) without a display link to manage.
            guard !viewportScheduled else { return }
            viewportScheduled = true
            DispatchQueue.main.async { [weak self] in self?.reportViewport() }
        }

        private func reportViewport() {
            viewportScheduled = false
            guard let viewport = currentViewport(), viewport != parent.controller.viewport else { return }
            parent.controller.viewport = viewport
        }

        /// The first visible line and how far into it the top edge is, from the
        /// first layout fragment under the top of the visible rect.
        func currentViewport() -> EditorViewport? {
            guard let textView,
                  let layoutManager = textView.textLayoutManager,
                  let contentManager = layoutManager.textContentManager
            else { return nil }
            let length = (textView.string as NSString).length
            guard length > 0 else { return EditorViewport(topLine: 1, fraction: 0) }
            let y = max(0, textView.visibleRect.minY - textView.textContainerOrigin.y)
            guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return nil }
            let offset = contentManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
            let frame = fragment.layoutFragmentFrame
            let fraction = min(1, max(0, (y - frame.minY) / max(1, frame.height)))
            return EditorViewport(topLine: line(atUTF16: offset, in: textView.string), fraction: fraction)
        }

        /// Scrolls so `line` (1-based) is at the top. Tests and the debug soak use it.
        func scrollToLine(_ line: Int) {
            guard let textView,
                  let layoutManager = textView.textLayoutManager,
                  let contentManager = layoutManager.textContentManager
            else { return }
            let starts = lineStartOffsets(textView.string)
            let offset = starts[min(max(line - 1, 0), starts.count - 1)]
            guard let location = contentManager.location(layoutManager.documentRange.location, offsetBy: offset),
                  let range = NSTextRange(location: layoutManager.documentRange.location, end: location)
            else { return }
            layoutManager.ensureLayout(for: range)
            textView.sizeToFit()
            guard let fragment = layoutManager.textLayoutFragment(for: location) else { return }
            textView.scroll(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y))
        }

        private func line(atUTF16 offset: Int, in text: String) -> Int {
            let starts = lineStartOffsets(text)
            var low = 0, high = starts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if starts[mid] <= offset { low = mid } else { high = mid - 1 }
            }
            return low + 1
        }

        /// UTF-16 offsets where each line starts (`\n`, `\r\n` or `\r`), cached until the next edit.
        private func lineStartOffsets(_ text: String) -> [Int] {
            if let lineStarts { return lineStarts }
            var starts = [0]
            var offset = 0
            var previousCR = false
            for unit in text.utf16 {
                offset += 1
                if unit == 0x0A {
                    if previousCR { starts[starts.count - 1] = offset } else { starts.append(offset) }
                } else if unit == 0x0D {
                    starts.append(offset)
                }
                previousCR = unit == 0x0D
            }
            lineStarts = starts
            return starts
        }
    }
}
#endif

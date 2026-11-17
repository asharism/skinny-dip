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
    /// View › Show Line Numbers (#76), applied live.
    var showsLineNumbers: Bool = true

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
        private var lines: LineNumbering?
        private(set) var gutter: NativeEditorGutter
        /// Where the current-line band was last drawn, so a caret move redraws only the two bands.
        var drawnCurrentLine: NSRect?

        init(parent: NativeEditorView) {
            self.parent = parent
            theme = NativeEditorTheme(vars: parent.themeVars)
            gutter = NativeEditorGutter(isVisible: parent.showsLineNumbers, theme: theme)
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
            gutter.digits = LineNumbering.digits(forLineCount: lineNumbering(of: parent.text).count)
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
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                center.addObserver(self, selector: #selector(windowKeyChanged(_:)), name: name, object: nil)
            }
            textView.postsFrameChangedNotifications = true
            center.addObserver(self, selector: #selector(frameChanged(_:)), name: NSView.frameDidChangeNotification, object: textView)
            return scrollView
        }

        func update(from parent: NativeEditorView) {
            self.parent = parent
            let next = NativeEditorTheme(vars: parent.themeVars)
            if next != theme, let textView {
                theme = next
                gutter.theme = next
                applyTheme(to: textView)
                restyleAll(textView)
                highlighter?.theme = next
                highlighter?.highlightNow()
            }
            if parent.showsLineNumbers != gutter.isVisible, let textView {
                gutter.isVisible = parent.showsLineNumbers
                applyGutterInsets(to: textView)
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
            linesDidChange()
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
            applyGutterInsets(to: textView)
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
            linesDidChange()
            refreshCurrentLine()
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
            refreshCurrentLine()
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

        // MARK: Line numbers (#76)

        /// Everything left of the text, 0 with the gutter hidden.
        var gutterWidth: CGFloat { gutter.width }

        /// Logical lines of `text`, cached until the next edit.
        func lineNumbering(of text: String) -> LineNumbering {
            if let lines { return lines }
            let computed = LineNumbering(text)
            lines = computed
            return computed
        }

        /// After an edit: the numbers below it may change, and the gutter widens
        /// only when the line count gains a digit.
        private func linesDidChange() {
            lines = nil
            guard let textView else { return }
            let digits = LineNumbering.digits(forLineCount: lineNumbering(of: textView.string).count)
            if digits != gutter.digits {
                gutter.digits = digits
                applyGutterInsets(to: textView)
            } else {
                invalidateGutter()
            }
        }

        private func applyGutterInsets(to textView: NSTextView) {
            textView.textContainerInset = NSSize(width: gutter.containerInsetWidth, height: theme.insets.top)
            textView.needsDisplay = true
        }

        @objc private func frameChanged(_ notification: Notification) {
            invalidateGutter()
            refreshCurrentLine()
        }

        @objc private func windowKeyChanged(_ notification: Notification) {
            guard let window = notification.object as? NSWindow, window === textView?.window else { return }
            refreshCurrentLine()
        }

        func textViewWritingToolsWillBegin(_ textView: NSTextView) {
            DispatchQueue.main.async { [weak self] in self?.refreshCurrentLine() }
        }

        func textViewWritingToolsDidEnd(_ textView: NSTextView) {
            DispatchQueue.main.async { [weak self] in self?.refreshCurrentLine() }
        }

        // MARK: Scroll sync (ADR-0006)

        @objc private func boundsChanged(_ notification: Notification) {
            invalidateGutter()
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
            return EditorViewport(topLine: lineNumbering(of: textView.string).line(atUTF16: offset), fraction: fraction)
        }

        /// Scrolls so `line` (1-based) is at the top. Tests and the debug soak use it.
        func scrollToLine(_ line: Int) {
            guard let textView,
                  let layoutManager = textView.textLayoutManager,
                  let contentManager = layoutManager.textContentManager
            else { return }
            let offset = lineNumbering(of: textView.string).start(ofLine: line)
            guard let location = contentManager.location(layoutManager.documentRange.location, offsetBy: offset),
                  let range = NSTextRange(location: layoutManager.documentRange.location, end: location)
            else { return }
            layoutManager.ensureLayout(for: range)
            textView.sizeToFit()
            guard let fragment = layoutManager.textLayoutFragment(for: location) else { return }
            textView.scroll(NSPoint(x: 0, y: fragment.layoutFragmentFrame.minY + textView.textContainerOrigin.y))
        }
    }
}
#endif

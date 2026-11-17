#if os(macOS)
import AppKit
import MarkdownCore

/// The native editor's line-number gutter (#76). It is not a ruler or a sibling
/// view: the text view draws the numbers itself, in its own left inset, from
/// `drawBackground(in:)`. The numbers scroll with the text for free, there is no
/// second view to keep in step with the clip view, and the layout comes from
/// `NSTextLayoutManager` fragments over the dirty rect only, so it stays on
/// TextKit 2. An `NSRulerView` makes `NSTextView` manage ruler markers and sits
/// outside the clip view, so it would also need its own background.
///
/// Geometry: with the gutter on, the text starts at the inline padding plus the
/// widest number's digits. The numbers end `gap` before the text, so the gutter
/// takes the place of the padding instead of adding to it.
@MainActor
struct NativeEditorGutter {
    var isVisible: Bool
    var theme: NativeEditorTheme
    /// Digits reserved for the widest number, from `LineNumbering.digits`.
    var digits: Int = 2

    var gap: CGFloat { 8 * theme.zoom }

    var digitWidth: CGFloat {
        ("0" as NSString).size(withAttributes: [.font: theme.font]).width
    }

    /// Everything left of the text: 0 when hidden.
    var width: CGFloat {
        isVisible ? theme.inlinePadding + CGFloat(digits) * digitWidth : 0
    }

    /// Where the text container starts. Without the gutter it is today's inline padding.
    var textOriginX: CGFloat {
        isVisible ? width : theme.inlinePadding
    }

    /// `textContainerInset.width` applies to both sides, so the right padding
    /// grows by the digits too. Moving only the left edge would need a
    /// `textContainerOrigin` override, which NSTextView's placeholder ignores.
    var containerInsetWidth: CGFloat { textOriginX }

    var lineHeight: CGFloat {
        theme.paragraphStyle.minimumLineHeight
    }

    func attributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        let style = (theme.paragraphStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.alignment = .right
        return [.font: theme.font, .foregroundColor: color, .paragraphStyle: style]
    }
}

/// One drawn row: a logical line's number and its first line fragment, in text view coordinates.
struct GutterRow: Equatable {
    var line: Int
    var rect: NSRect
}

extension NativeEditorTextView {
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        editorCoordinator?.drawCurrentLine(in: rect, textView: self)
        editorCoordinator?.drawGutter(in: rect, textView: self)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        editorCoordinator?.refreshCurrentLine()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        editorCoordinator?.refreshCurrentLine()
        return resigned
    }
}

extension NativeEditorView.Coordinator {
    /// The numbered rows whose first line fragment meets `rect`. Each logical
    /// line gets one row, level with its first fragment; wrapped rows get none.
    /// Walks layout fragments from the top of `rect` down, never the whole document.
    func gutterRows(in rect: NSRect, textView: NSTextView) -> [GutterRow] {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return [] }
        let lines = lineNumbering(of: textView.string)
        let origin = textView.textContainerOrigin
        let documentStart = layoutManager.documentRange.location
        let length = (textView.string as NSString).length
        let lastLineIsEmpty = lines.starts.last == length
        var rows: [GutterRow] = []
        var lastFragmentBottom: CGFloat = 0
        var reachedEnd = length == 0

        let top = max(0, rect.minY - origin.y)
        let start = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: top))?.rangeInElement.location
        if let start {
            layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
                let frame = fragment.layoutFragmentFrame
                guard frame.minY + origin.y <= rect.maxY else { return false }
                lastFragmentBottom = frame.maxY
                let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
                let line = lines.line(atUTF16: offset)
                if lines.start(ofLine: line) == offset, let first = fragment.textLineFragments.first {
                    rows.append(GutterRow(line: line, rect: Self.rect(of: first, in: frame, origin: origin)))
                }
                let fragmentEnd = contentManager.offset(from: documentStart, to: fragment.rangeInElement.endLocation)
                if fragmentEnd >= length {
                    reachedEnd = true
                    // TextKit 2 gives the empty last line its own line fragment
                    // inside the last paragraph.
                    if lastLineIsEmpty, fragment.textLineFragments.count > 1,
                       let extra = fragment.textLineFragments.last, extra.characterRange.length == 0 {
                        rows.append(GutterRow(line: lines.count, rect: Self.rect(of: extra, in: frame, origin: origin)))
                        lastFragmentBottom = -1
                    }
                }
                return true
            }
        } else if top > 0, let last = layoutManager.textLayoutFragment(for: layoutManager.documentRange.endLocation) ?? lastFragment(layoutManager) {
            lastFragmentBottom = last.layoutFragmentFrame.maxY
            reachedEnd = true
        }

        // An empty document, or an empty last line TextKit didn't give a fragment.
        if reachedEnd, lastLineIsEmpty, lastFragmentBottom >= 0, rows.last?.line != lines.count {
            let y = origin.y + lastFragmentBottom
            let row = NSRect(x: origin.x, y: y, width: textView.bounds.width - origin.x, height: gutter.lineHeight)
            if row.intersects(rect) { rows.append(GutterRow(line: lines.count, rect: row)) }
        }
        return rows
    }

    func drawGutter(in rect: NSRect, textView: NSTextView) {
        guard gutter.isVisible, rect.minX < gutter.width else { return }
        let numberRight = gutter.textOriginX - gutter.gap
        let muted = gutter.attributes(color: gutter.theme.muted)
        let current = gutter.attributes(color: gutter.theme.foreground)
        let currentLine = showsCurrentLine ? currentLineNumber() : nil
        for row in gutterRows(in: rect, textView: textView) {
            let box = NSRect(x: 0, y: row.rect.minY, width: numberRight, height: row.rect.height)
            let attributes = row.line == currentLine ? current : muted
            ("\(row.line)" as NSString).draw(with: box, options: [.usesLineFragmentOrigin], attributes: attributes)
        }
    }

    // MARK: Current line (#77)

    /// The caret's whole logical line, every wrapped row of it, as one band
    /// across the text view. Nil for a non-empty selection. Focus is checked
    /// separately, by `showsCurrentLine`.
    func currentLineRect() -> NSRect? {
        guard let textView,
              let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return nil }
        let ranges = textView.selectedRanges.map(\.rangeValue)
        guard ranges.count == 1, let caret = ranges.first, caret.length == 0 else { return nil }
        let lines = lineNumbering(of: textView.string)
        let line = lines.line(atUTF16: caret.location)
        let start = lines.start(ofLine: line)
        let end = line < lines.count ? lines.start(ofLine: line + 1) : (textView.string as NSString).length
        let origin = textView.textContainerOrigin
        let documentStart = layoutManager.documentRange.location

        // The empty last line has no paragraph of its own: use its gutter row.
        if line == lines.count, start == end {
            var row = NSRect(x: 0, y: origin.y, width: textView.bounds.width, height: gutter.lineHeight)
            if let last = lastFragment(layoutManager) {
                let frame = last.layoutFragmentFrame
                if let extra = last.textLineFragments.last, last.textLineFragments.count > 1, extra.characterRange.length == 0 {
                    row.origin.y = frame.minY + extra.typographicBounds.minY + origin.y
                    row.size.height = extra.typographicBounds.height
                } else {
                    row.origin.y = frame.maxY + origin.y
                }
            }
            return row
        }

        guard let location = contentManager.location(documentStart, offsetBy: start) else { return nil }
        var frame: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
            let offset = contentManager.offset(from: documentStart, to: fragment.rangeInElement.location)
            guard offset < end || frame == nil else { return false }
            var fragmentFrame = fragment.layoutFragmentFrame
            // The last paragraph's fragment also holds the empty line after a
            // trailing break; that row belongs to the next line.
            if let extra = fragment.textLineFragments.last, fragment.textLineFragments.count > 1,
               extra.characterRange.length == 0 {
                fragmentFrame.size.height = extra.typographicBounds.minY
            }
            frame = frame.map { $0.union(fragmentFrame) } ?? fragmentFrame
            return true
        }
        guard let frame else { return nil }
        return NSRect(x: 0, y: frame.minY + origin.y, width: textView.bounds.width, height: frame.height)
    }

    /// Only while the editor has focus in the key window, the selection is
    /// empty and Writing Tools isn't rewriting the text.
    var showsCurrentLine: Bool {
        guard let textView, let window = textView.window else { return false }
        return window.firstResponder === textView
            && window.isKeyWindow
            && textView.selectedRange().length == 0
            && !textView.isWritingToolsActive
    }

    private func currentLineNumber() -> Int? {
        guard let textView else { return nil }
        return lineNumbering(of: textView.string).line(atUTF16: textView.selectedRange().location)
    }

    func drawCurrentLine(in rect: NSRect, textView: NSTextView) {
        guard showsCurrentLine, let band = currentLineRect(), band.intersects(rect) else { return }
        gutter.theme.currentLine.setFill()
        band.intersection(rect).fill(using: .sourceOver)
    }

    /// After a caret move, an edit or a focus change: redraws the old band and the new one.
    func refreshCurrentLine() {
        guard let textView else { return }
        let next = showsCurrentLine ? currentLineRect() : nil
        if let drawnCurrentLine { textView.setNeedsDisplay(drawnCurrentLine) }
        if let next { textView.setNeedsDisplay(next) }
        // The old and new numbers change colour too.
        if drawnCurrentLine != next { invalidateGutter() }
        drawnCurrentLine = next
    }

    /// The gutter strip of the visible rect, for redraws after an edit or a scroll.
    func invalidateGutter() {
        guard gutter.isVisible, let textView else { return }
        let visible = textView.visibleRect
        textView.setNeedsDisplay(NSRect(x: 0, y: visible.minY, width: gutter.width, height: visible.height))
    }

    private static func rect(of line: NSTextLineFragment, in frame: CGRect, origin: NSPoint) -> NSRect {
        let bounds = line.typographicBounds
        return NSRect(
            x: frame.minX + bounds.minX + origin.x,
            y: frame.minY + bounds.minY + origin.y,
            width: bounds.width,
            height: bounds.height
        )
    }

    private func lastFragment(_ layoutManager: NSTextLayoutManager) -> NSTextLayoutFragment? {
        var last: NSTextLayoutFragment?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.endLocation, options: [.reverse, .ensuresLayout]) { fragment in
            last = fragment
            return false
        }
        return last
    }
}
#endif

import AppKit
@_spi(Plugins) import STTextView

/// STTextView plus Sublime-style multi-cursor keys, built only on STTextView's public API
/// and Apple's public TextKit 2 API (`NSTextLayoutManager.textSelections`,
/// `NSTextSelectionNavigation`). STTextView itself natively adds a caret on ⌃⇧-click.
final class SpikeTextView: STTextView {

    // MARK: Keys

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, handleMultiCursorKey(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleMultiCursorKey(event) { return }
        super.keyDown(with: event)
    }

    private func handleMultiCursorKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if flags == .command, event.charactersIgnoringModifiers == "d" {
            addNextOccurrence()
            return true
        }
        if flags == [.control, .shift] {
            switch event.keyCode {
            case 126: addCaret(direction: .up); return true      // ↑
            case 125: addCaret(direction: .down); return true    // ↓
            default: break
            }
        }
        return false
    }

    // MARK: ⌘-click

    override func mouseDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard flags == .command, event.clickCount == 1, isSelectable else {
            super.mouseDown(with: event)
            return
        }
        // Point in text-layout coordinates (the content view sits at contentFrame.origin).
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: viewPoint.x - contentFrame.minX, y: viewPoint.y - contentFrame.minY)
        let added = textLayoutManager.textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: textLayoutManager.documentRange.location,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: textLayoutManager.usageBoundsForTextContainer
        )
        setSelections(textLayoutManager.textSelections + added)
    }

    // MARK: ⌃⇧↑ / ⌃⇧↓

    private func addCaret(direction: NSTextSelectionNavigation.Direction) {
        let selections = textLayoutManager.textSelections
        let sorted = selections.sorted { lhs, rhs in
            guard let l = lhs.textRanges.first?.location, let r = rhs.textRanges.first?.location else { return false }
            return l.compare(r) == .orderedAscending
        }
        guard let edge = direction == .up ? sorted.first : sorted.last else { return }
        let caret = NSTextSelection(
            direction == .up ? edge.textRanges.first!.location : edge.textRanges.last!.endLocation,
            affinity: .downstream
        )
        guard let moved = textLayoutManager.textSelectionNavigation.destinationSelection(
            for: caret, direction: direction, destination: .character, extending: false, confined: false
        ), let movedLocation = moved.textRanges.first?.location,
            movedLocation.compare(caret.textRanges.first!.location) != .orderedSame
        else { return }
        setSelections(selections + [moved])
    }

    // MARK: ⌘D

    /// Sublime: with only carets, select the word under each caret; otherwise add the
    /// next occurrence (wrapping) of the most recent selection's text.
    private func addNextOccurrence() {
        guard let string = text as NSString?, string.length > 0 else { return }
        let ranges = textLayoutManager.textSelections.flatMap(\.textRanges).compactMap(nsRange)
        guard let last = ranges.last else { return }

        if ranges.allSatisfy({ $0.length == 0 }) {
            let words = ranges.compactMap { wordRange(at: $0.location, in: string) }
            guard !words.isEmpty else { return }
            setSelections(words.compactMap(selection))
            return
        }

        guard last.length > 0 else { return }
        let needle = string.substring(with: last)
        let after = NSRange(location: NSMaxRange(last), length: string.length - NSMaxRange(last))
        var found = string.range(of: needle, options: [], range: after)
        if found.location == NSNotFound {
            found = string.range(of: needle, options: [], range: NSRange(location: 0, length: last.location))
        }
        guard found.location != NSNotFound, !ranges.contains(found), let added = selection(for: found) else { return }
        setSelections(textLayoutManager.textSelections + [added])
        scrollRangeToVisible(found)
    }

    private func wordRange(at location: Int, in string: NSString) -> NSRange? {
        let isWord: (unichar) -> Bool = { c in
            guard let scalar = Unicode.Scalar(c) else { return false }
            return CharacterSet.alphanumerics.contains(scalar) || c == 95 // "_"
        }
        var start = location, end = location
        while start > 0, isWord(string.character(at: start - 1)) { start -= 1 }
        while end < string.length, isWord(string.character(at: end)) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    // MARK: Helpers

    private func nsRange(_ textRange: NSTextRange) -> NSRange? {
        let cm = textContentManager
        let start = cm.offset(from: cm.documentRange.location, to: textRange.location)
        let length = cm.offset(from: textRange.location, to: textRange.endLocation)
        return NSRange(location: start, length: length)
    }

    private func selection(for range: NSRange) -> NSTextSelection? {
        let cm = textContentManager
        guard let start = cm.location(cm.documentRange.location, offsetBy: range.location),
              let end = cm.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return nil }
        return NSTextSelection(range: textRange, affinity: .downstream, granularity: .character)
    }

    /// Set selections and ask STTextView to redraw carets and highlights through public API.
    private func setSelections(_ selections: [NSTextSelection]) {
        textLayoutManager.textSelections = selections
        textLayoutManager.textViewportLayoutController.layoutViewport()
        updateInsertionPointStateAndRestartTimer()
        needsDisplay = true
    }
}

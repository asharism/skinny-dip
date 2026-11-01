import AppKit
import SwiftUI

/// Plain NSTextView on TextKit 2, with every native writing feature the scorecard
/// tests switched on. No third-party code and no multi-caret layer: this is the baseline.
struct Editor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            fatalError("scrollableTextView() did not return an NSTextView")
        }
        // scrollableTextView() builds a TextKit 2 view on macOS 13+. Fail loudly if it
        // ever falls back to TextKit 1, since the spike is about TextKit 2.
        precondition(textView.textLayoutManager != nil, "Expected a TextKit 2 NSTextView")

        // Plain-text Markdown editing.
        textView.isRichText = false
        textView.importsGraphics = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Soft wrap to the view width.
        scrollView.hasHorizontalScroller = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        // Undo and find.
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Native writing features the scorecard checks.
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.inlinePredictionType = .yes
        textView.writingToolsBehavior = .complete

        // Off: these would rewrite Markdown syntax.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.string = SampleDocument.text
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

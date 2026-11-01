import AppKit
import STTextView
import SwiftUI

/// STTextView wrapped for SwiftUI, configured with every native text service the scorecard checks.
struct Editor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = SpikeTextView.scrollableTextView()
        scrollView.hasHorizontalScroller = false
        let textView = scrollView.documentView as! SpikeTextView

        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor

        // Soft wrap: the text container tracks the view width.
        textView.isHorizontallyResizable = false

        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.highlightSelectedLine = true
        textView.isIncrementalSearchingEnabled = true

        // Native text services STTextView exposes.
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticTextCompletionEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false  // smart quotes off

        textView.text = SampleDocument.text
        textView.textSelection = NSRange(location: 0, length: 0)

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

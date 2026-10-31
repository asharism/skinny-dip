# CodeMirror 6 in a web view is the Mac editor

The Mac editor is CodeMirror 6 running in a `WKWebView`, chosen over Apple's `NSTextView` and STTextView after building all three as kept evaluation apps (`Spikes/Editors/`, issue #1). It is the only candidate with full Sublime-style multi-cursor (⌘D, add cursor above/below, ⌘-click) under a permissive (MIT) license; `NSTextView` cannot hold multiple empty carets, and STTextView needed our own key wiring for most of those gestures and is GPL-3.0 or paid. In hand testing it felt fastest on the 10,000-line document.

## Consequences

- **Memory**: the measured footprint is the highest of the three: about 254 MB (app 83 MB + WebContent 147 MB + GPU/Networking 24 MB) against 65 MB for `NSTextView` and 74 MB for STTextView. Accepted for a scratchpad; the Preview (P3) needs a web view anyway, so P3 should try to share one page or WebContent process between editor and Preview.
- **We own a Swift↔JS bridge** for things `NSTextView` gives for free: undo/redo and the document's edited state, Select All beyond the visible viewport, the Edit menu, and a find panel (CodeMirror's own on ⌘F). MarkEdit (MIT) is the reference implementation.
- **Native text features ride on WebKit**: spell check, autocorrect and Writing Tools work through `contenteditable` attributes and `writingToolsBehavior`; they must be verified in the real app, not assumed.
- **Copy stays pure Swift** (ADR-0001): the editor reports text and selection to Swift; it never produces the clipboard HTML.
- The editor bundle is prebuilt with esbuild and checked in, so the app builds without Node.
- The iOS editor (P6) is still open: CodeMirror also runs on iOS, which may beat a separate native text view.

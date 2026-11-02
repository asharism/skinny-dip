# Paste as Markdown converts HTML with SwiftSoup, inside MarkdownCore

Paste as Markdown (P4) turns another app's rich-text clipboard into Markdown Source in `MarkdownCore` (`HTMLToMarkdown`, chosen by `PasteAsMarkdown`), using SwiftSoup (MIT) to parse the HTML. That makes SwiftSoup MarkdownCore's second dependency, after `swift-markdown`.

HTML pasted from Word, Outlook, Gmail and Google Docs is badly formed. It's namespaced (`<o:p>`), full of conditional comments, has unclosed tags, carries structure in inline `style` (fake Word lists, bold via `font-weight`), and buries everything in `div`/`span` soup. We rejected a hand-rolled scanner because most of its code would go into recovering tags rather than mapping structure. We rejected `NSAttributedString(html:)` because it needs AppKit/UIKit on the main thread, which pushes the logic out of the UI-free core, and it flattens lists and tables into styled runs we'd have to reverse-engineer. We also rejected converting in a WebView with JS (Turndown and similar), since copy and paste stay pure Swift and testable without a simulator. SwiftSoup is pure Swift and runs on both Mac and iOS, and its tolerant parser does the recovery a browser would.

⌘V uses the first of these flavors that's present:
1. Our own Markdown flavor, pasted verbatim.
2. HTML (or a web archive's main resource), converted. When the HTML is just styled plain text (a copy from a code editor), the plain-text flavor is pasted instead, so Markdown copied from VS Code isn't escaped.
3. Plain text.

The converter maps only what Bare HTML can express and drops everything else: fonts, colors, classes, `script`/`style`, and **images**, which a text scratchpad can't hold. Links survive only for `http`, `https` and `mailto`; otherwise only the label is kept. Markdown punctuation in text is escaped where it would otherwise become syntax.

Paste as Markdown fits ADR-0002 because the user starts it: the converted text is inserted once, at the cursor, as a single undoable edit, and Skinny never rewrites it afterwards.

## Consequences

- Golden pairs live in `Tests/MarkdownCoreTests/Golden/paste/` (`<name>.html` → `<name>.md`). Real clipboard captures from Paste Targets (`capture-word-mac`, `capture-chrome`, `capture-safari`) are added there as they're tested.
- Round-trip invariant: for every `Golden/plain` case, `BareHTML → HTMLToMarkdown → BareHTML` must reproduce the same HTML, so our own copy pastes back losslessly even without the Markdown flavor.
- No SwiftSoup type crosses MarkdownCore's public API, so replacing it later touches only `HTMLToMarkdown.swift`.

# Separate Preview web view and Preview-only code language hints

The live Preview (P3) uses its own `WKWebView` loading `preview.html`, separate from the CodeMirror editor web view (ADR-0003). The spike measured ~254 MB for one editor web stack; a second Preview web view adds memory but keeps the editor and Preview lifecycles independent, avoids reloading either pane on every keystroke, and sidesteps sharing one HTML page between two very different JS bundles.

Fenced code blocks render as plain `<pre><code>` in Bare HTML (ADR-0001), so highlight.js cannot rely on `class="language-swift"`. For Preview only, `PreviewHTML` adds a `data-lang` attribute on `<code>` when the fence names a language. Copy as Rich Text still uses `BareHTML`, so pasted code never carries language hints or syntax-color markup.

## Consequences

- Two WebKit content processes on Mac until a later optimization proves a shared process is worth the coupling.
- Preview syntax highlighting is cosmetic; paste fidelity stays unchanged.
- `preview.html` calls `render(html)` to swap body HTML and re-run highlight.js while preserving scroll position.

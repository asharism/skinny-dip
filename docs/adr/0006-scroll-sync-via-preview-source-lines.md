# Scroll sync through Preview-only source-line anchors

Scroll sync moves into the MVP (it was deferred as hard to get right). It is **one-way**: scrolling the Editor scrolls the Preview to the matching place, and scrolling the Preview leaves the Editor alone. It is on by default, with a toggle in the Preview Card header.

The mapping is block by block. `PreviewHTML` adds `data-source-line="N"` (1-based) to each top-level block element: headings, paragraphs, lists, blockquotes, tables, code blocks and rules. N comes from swift-markdown's `SourceRange`. The Editor reports the first visible line. The Preview finds the last anchor at or above that line and the next anchor below it, interpolates between their offsets, and scrolls there.

The anchors are Preview-only, like `data-lang` (ADR-0004). `BareHTML`, and so Copy as Rich Text, never emits them, and a golden test proves that.

We rejected two-way sync for the MVP. With two scroll sources, each one moves the other, which needs guards against feedback loops and jitters on images and tables. The workflow is "write on the left, glance right". If two-way is missed, it can be added on top of the same anchors.

## Consequences

- `PreviewHTML` and `BareHTML` differ in one more attribute. The existing test that checks "Preview equals Bare apart from `data-lang`" grows to cover `data-source-line`.
- The Preview's `render(html)` keeps the scroll position only while sync is off. While sync is on, the Editor's position wins after every render.
- Anchors sit on top-level blocks only, so a single 300-line list scrolls smoothly only by interpolation. That's acceptable for email-sized documents.

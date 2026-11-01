# Skinny Dip — Build Plan

Oct 30, 2026 · @Hitesh

## TL;DR

Build Skinny Dip, a small SwiftUI multiplatform app whose one job is: **write Markdown, copy it out as clean rich text that survives Outlook, Word, Gmail and Teams.** The Gemini FRD is a sound start but optimizes the wrong thing (raw editor speed) and misses the real hard part (clipboard fidelity).

- **Product in one line:** a Markdown scratchpad with a live preview and a one-key *Copy as Rich Text* (⌘C).
- **Core bet:** one render pipeline. Preview uses any CSS theme; Copy writes bare semantic HTML + Markdown, so pasted text adopts the destination's styling.
- **Platform floor:** macOS 26 / iOS 26. Unlocks SwiftUI's native `WebView`/`WebPage` and the newer `TextEditor` APIs on all three devices.
- **Structure:** Xcode multiplatform app + a local Swift package (`MarkdownCore`) holding all logic, so TDD runs via `swift test` with no simulator.
- **iPad/iPhone:** designed in from Phase 0 (shared core, platform-specific editor wrapper), shipped after the Mac app is solid.

**Success = you stop opening VS Code to preview-and-copy.**

## Review of the Gemini FRD

Keep the hybrid idea (native text view + web preview). Change the items below; most are cross-platform blockers or wrong framings.

| FRD item | Verdict | Why / change |
| --- | --- | --- |
| FR-1.1 `HSplitView` | Change | macOS-only. Build a small shared `SplitPane` (HStack + drag handle) on iPad/Mac; editor/preview toggle on iPhone. |
| FR-1.4 `DocumentGroup` | Keep | Works on macOS, iPadOS, iOS. Use `FileDocument` with the `net.daringfireball.markdown` UTType. |
| FR-2.1 TextKit 2 `NSTextView` | Keep, abstract | Wrap behind an `EditorView` protocol: `NSViewRepresentable` on Mac, `UIViewRepresentable` (UITextView, also TextKit 2) on iOS. |
| FR-2.2 "non-contiguous layout" | Reword | That is a TextKit 1 flag. TextKit 2 is viewport-based by design; requirement becomes "smooth scroll on a 10k-line file". |
| FR-3.1 `WKWebView` reload | Change | Reloading HTML per keystroke flashes and loses scroll. Load a shell page once; push new body via JS `render(html)`. Use SwiftUI `WebView` + `WebPage` (26+). |
| FR-3.2 150–250 ms debounce, off-main parse | Keep | Implement as a cancellable `Task` + parser `actor`. |
| FR-3.3 highlight.js | Keep | Bundle locally (no CDN). Preview only; pasted code is plain monospace (ADR-0001). |
| NFR-1 sub-16 ms input | Keep | Easy with a plain-text view; the risk is editor syntax coloring, so color only the visible range. |
| NFR-2 < 100 MB idle | Relax | WebKit runs out-of-process; measure app + WebContent together, target \~150 MB. |
| Phase 4 scroll sync | Defer, then moved into MVP | One-way, Editor → Preview, matched block by block via Preview-only source-line anchors (ADR-0006, P5b). |
| **Missing: Copy as Rich Text** | **Add — P0** | The actual goal. See pipeline section. |
| **Missing: editor Markdown coloring** | Add — P2 | Headings, emphasis, code spans; keeps Sublime-like feel. |
| **Missing: test strategy** | Add | Golden-file tests for HTML output; paste matrix for target apps. |

## Architecture

One Xcode multiplatform target plus a local Swift package. Only two small pieces differ per platform, so the iPad/iPhone port is mostly layout work.

&#91;embedded content: app architecture · 4 components in a shared shell\]

**Project layout**

```
SkinnyDip/
  App/            SwiftUI shell, DocumentGroup, commands, settings
  Platform/       EditorView+Mac.swift, EditorView+iOS.swift, Clipboard+*.swift
  Resources/      preview.html, theme.css, highlight.min.js
Packages/MarkdownCore/
  Sources/        Parser actor, HTML renderer, document model
  Tests/          golden files: input.md -> expected.html
```

**Stack choices**

| Layer | Choice | Note |
| --- | --- | --- |
| Min OS | macOS 26, iOS/iPadOS 26 | Native SwiftUI `WebView`/`WebPage`; newest `TextEditor` APIs |
| Parser | Apple `swift-markdown` (cmark-gfm inside) | GFM tables, task lists; AST visitor for custom HTML |
| Editor | CodeMirror 6 in a `WKWebView` (ADR-0003) | MIT; multi-cursor built in; see next section |
| Preview | SwiftUI `WebView` + bundled HTML/CSS/JS | No network; JS bridge for `render()` only |
| Tests | `swift test` (core), `xcodebuild test` (UI smoke) | Core tests run fast, CLI-friendly for Claude Code |

## Editor, BBEdit/Sublime grade

**Decision: CodeMirror 6 in a `WKWebView`** (ADR-0003, issue #1). All three candidates were built as kept evaluation apps in `Spikes/Editors/` (Apple `NSTextView`, STTextView, CodeMirror 6) and tried on the same 10,000-line document. CodeMirror is the only one with full Sublime-style multi-cursor under a permissive license, and it felt fastest. It costs the most memory (≈254 MB with its WebKit processes vs 65–74 MB native) and needs a Swift↔JS bridge.

| Pro-editor feature | How |
| --- | --- |
| Large files, smooth scroll | CodeMirror renders only the viewport; Lezer parses incrementally |
| Multi-cursor | Built in: ⌘D next occurrence, ⌘-click, ⌘⌥↑/↓; we add ⌃⇧↑/↓ (macOS may intercept it) |
| Markdown syntax coloring | `@codemirror/lang-markdown` (GFM); code-fence languages via `@codemirror/language-data` later |
| List continuation, smart indent | `insertNewlineContinueMarkup` and indent commands from lang-markdown |
| Find and replace | CodeMirror's search panel on ⌘F |
| Spelling, autocorrect, Writing Tools | WebKit `contenteditable` attributes + `writingToolsBehavior`; verify in the real app |
| Undo, edited state, Select All, Edit menu | Bridged to Swift by us (MarkEdit is the MIT reference) |

**Caveats**

- The bridge is ours to own: undo grouping, document edited state, Select All past the viewport, the Edit menu and right-click menu.
- WebKit IME bugs (MarkEdit #956, #358) and Writing Tools changes arrive with macOS releases; re-run the spike apps after each one.
- The editor bundle is built with esbuild from pinned packages and checked in; the app builds without Node.
- The editor is the biggest chunk of work; P2 and P5 grow accordingly.

## Copy-to-destination pipeline

Paste adopts the destination's styling: the clipboard carries **structure, never looks**. The app can use any theme; Outlook, Word or Gmail apply their own fonts and heading styles.

1. **One renderer** — `MarkdownCore` emits clean semantic HTML only: `h1–h6`, `p`, `ul/ol/li`, `strong/em`, `a`, `blockquote`, `table`, `pre/code`, `hr`. No `class`, `style`, `font` or color attributes. The preview wraps it in theme CSS; the clipboard gets it bare. Copy is pure Swift, no JS.
2. **Pasteboard flavors** — `public.html` (minimal `<html><body>` wrapper, UTF-8) + `public.utf8-plain-text` (the Markdown). **No RTF**: `NSAttributedString(html:)` bakes in fonts, which would override the destination.
3. **What the destination does** — Word/Outlook map `h1` to their Heading 1 style and `p` to Normal, so text takes the document or email theme; Gmail, Apple Mail and Teams use their compose defaults.
4. **Selection copy** — editor only. The selected text is parsed as a standalone document, with the full document's link reference definitions appended. The plain-text flavor is the exact selected text. ⌘C in the preview runs Copy as Rich Text on the whole document (never WebKit's styled copy).
5. **Pasting back into Skinny Dip** — our own copies paste as their Markdown flavor, never an HTML → Markdown round trip.

**Rendering rules**

| Element | Bare-HTML result | Default |
| --- | --- | --- |
| Tables | Borderless grid in Outlook/Word without help | `border="1"` attribute (structural, not CSS), on by default, toggle in settings |
| Headings in email | `h1` can look oversized | Demote one level, on by default; `h6` stays `h6` |
| Line breaks | CommonMark joins lines ("Thanks,\nHitesh" → one line) | Every newline is `<br>`, on by default; setting restores CommonMark |
| Raw HTML in Markdown | Would leak `style`/`class`/`font` | Escaped (shown as text) in preview and copy |
| Images | Local paths mean nothing in an inbox | `<img>` for `http(s)` URLs only; local paths render as alt text |
| Code blocks | Word uses its preformatted style; mail clients go monospace | Accept |
| Task lists | Checkbox inputs get stripped | Render as ☐ / ☑ characters |

**Commands**

| Command | Key | Output |
| --- | --- | --- |
| Copy as Rich Text | ⌘C | Bare HTML + Markdown, selection or whole doc |
| Copy as Markdown | ⌘⇧C | Markdown text only |
| Copy as HTML | ⌥⌘C | HTML string as plain text |
| Paste as Markdown (P4) | ⌘V | Rich text from other apps converted to Markdown; images and styling dropped |
| Paste and Match Style | ⌥⇧⌘V | Plain text, unconverted |

**Paste test matrix** (manual, each release): Copy as Rich Text from `docs/paste-matrix/fixture.md` into every Paste Target and log pass/fail per element in `docs/paste-matrix/results.md`. Check: text takes destination font, headings map to styles, nested lists, tables, code, links, line breaks, web images.

- **Tier 1** (a failure blocks the release; wins when targets disagree): new Outlook, Outlook for Mac, Teams. Failures become GitHub issues.
- **Tier 2** (fix when cheap; known defects can ship): Word, Gmail web, Apple Mail, Google Docs.

First run at the P2 gate; it also confirms table borders and heading sizes in Outlook and Teams.

## MVP scope

MVP = the smallest app that replaces the Sublime + VS Code preview round-trip on the Mac.

**In**

- Open/save `.md` files (DocumentGroup: autosave, versions, recents, Finder double-click)
- Editor: monospace, soft wrap, undo, native Mac text navigation, find (⌘F), multi-cursor (⌘D, add cursor above/below, ⌘-click), spell check, dictation, Writing Tools
- Live preview, debounced, scroll position kept across updates
- GFM: tables, task lists, strikethrough, autolinks, fenced code with highlighting
- Copy as Rich Text (⌘C), Copy as Markdown (⌘⇧C), Copy as HTML (⌥⌘C)
- Paste as Markdown (⌘V) — P4
- Toggle preview (⌘⇧P), light/dark follows system
- UI Shell (P5b, ADR-0005, `docs/design/ui-shell.md`): Rex-style Tab strip (one document per Tab), Editor and Preview as floating Cards (side by side or stacked, maximize, hide Preview), Copy split button with a confirmation, Card footers with render-option chips, eight themes (four light/dark pairs, Match System), editor font size
- Scroll sync, one-way Editor → Preview (ADR-0006)
- Line height 1.65 in the Editor, 1.6 in the Preview
- Untitled document on launch (ordinary DocumentGroup document; a persistent scratchpad can come later)

**Out (for now)**

- Two-way scroll sync, theme import or editing, window translucency, font-family settings, plugins
- WYSIWYG / Notes-style editing (ADR-0002); live-preview styling in the editor is a maybe for P5
- Local images, image paste, embedding images in the clipboard
- Copying a preview selection
- Math/LaTeX, Mermaid, footnotes beyond GFM
- Export to PDF/DOCX (the paste covers it; revisit later)
- iCloud sync, folder/sidebar browser, more than two Cards per Tab
- App Store release (run locally with a personal team first)

## Roadmap

Seven phases, each closed by a testable gate. P2 is the payoff: write, ⌘C, paste into Outlook, no VS Code. Copy comes before the preview because copy is why the app exists and works without one.

| Phase | Scope | Gate |
| --- | --- | --- |
| P0 | Xcode multiplatform app + `MarkdownCore` package + `swift-markdown` | First red test (`# Hello` → `<h1>Hello</h1>`) goes green |
| P1 | Renderer: GFM, rendering rules above, Selection Copy | Golden tests pass for every element and rule |
| ✓ | Editor spike: NSTextView vs STTextView vs CodeMirror 6 | Done: CodeMirror 6, ADR-0003 |
| P2 | Mac shell: DocumentGroup, editor, Copy as Rich Text / Markdown / HTML | First paste matrix run; Tier 1 passes |
| P3 | Live preview: `WebView`, `render(html)`, debounce, scroll kept, highlight.js | Preview updates without flashing on a 10k-line file |
| P4 | Paste as Markdown (HTML → Markdown converter) | Golden tests for pasted Outlook/Word/web HTML |
| P5 | Editor quality: Markdown coloring, list continuation, smart indent | Typing latency holds on a 10k-line file |
| P5b | UI Shell: themes and Cards, Tab strip (spike first), Copy split button and footers, scroll sync, theme menu and Settings ▸ Appearance (ADR-0005, ADR-0006, `docs/design/ui-shell.md`). Starts after the P2 paste-matrix gate (#7). | Tabs switch without flashing; every theme passes the contrast test; scroll sync tracks a 10k-line file; the paste matrix is unchanged |
| P6 | iPad/iPhone: `SplitPane`, editor/preview toggle, iOS editor and clipboard | Runs on device; paste matrix on iOS targets |

**How we work it (Claude Code + TDD)**

- Each phase starts with failing tests in `MarkdownCore/Tests` (golden `.md` → `.html` pairs), then code until green.
- UI pieces get thin smoke tests via `xcodebuild test`; layout is judged by running the app, not by tests.
- One PR-sized story per session; I draft the failing tests, you review, I implement.

**First session checklist (P0)**

- [x] Install Xcode (27.2 installed; deployment target stays macOS/iOS 26)
- [x] Accept the Xcode license
- [ ] Sign in with Apple ID in Xcode (free personal team is enough to run on your Mac and own iPhone; not needed for the Mac build, which signs ad hoc)
- [x] Create multiplatform app `SkinnyDip` (`com.hitesh.SkinnyDip`) via XcodeGen `project.yml`; local package `MarkdownCore`; `swift-markdown` 0.9.0
- [x] Declare `.md` document type (`net.daringfireball.markdown`) in Info.plist
- [x] First red test: `# Hello` renders `<h1>Hello</h1>`
- [x] Test reviewed; green

## Risks and open questions

| Risk | Mitigation |
| --- | --- |
| Pasted formatting differs per client (esp. Outlook's Word engine, Gmail) | Paste matrix each release; tune presets on real results; keep HTML simple (no flex/grid) |
| Editor coloring hurts typing latency on big files | Color visible range only, debounced; measure with Instruments early |
| SwiftUI `WebView`/`TextEditor` 26 APIs are first-generation | Hide behind protocols; fall back to `WKWebView` / `UITextView` wrappers if needed |
| Scope creep into a full IDE | MVP list above is the contract; new features need a paste-workflow reason |
| Swift learning curve | Logic in `MarkdownCore` (pure Swift, TDD); UI kept thin |

**Open questions**

- [x] Editor engine: CodeMirror 6 in a web view (ADR-0003).
- [x] Paste targets: Tier 1 new Outlook, Outlook for Mac, Teams; Tier 2 Word, Gmail, Apple Mail, Google Docs.
- [x] Table borders: on by default. Heading demotion: on; `h6` stays `h6`.
- [x] Raw HTML in Markdown: escaped.
- [x] Copy styling: bare HTML, no inliner (ADR-0001).
- [x] Source of truth: the Markdown text as typed; no WYSIWYG (ADR-0002).

**Prior art worth reading**

- [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) — open-source native Mac Markdown editor; editor is CodeMirror 6 inside a native shell, handles 10 MB files, preview via an extension. Good reference for the hybrid pattern.
- [codeink](https://github.com/NeckBeardPrince/codeink) — computed-style inlining for Outlook paste. The approach we rejected (ADR-0001).
- [PasteRich](https://github.com/RamonRiosJr/PasteRich) — Markdown → HTML/RTF clipboard daemon; validates the multi-flavor approach.
- &#32;[WWDC25: rich text in SwiftUI](https://nonstrict.eu/wwdcindex/wwdc2025/280/) and [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-use-rich-text-editing-with-textview-and-attributedstring) — `TextEditor` + `AttributedString` (iOS/macOS 26).
- [swift-cmark (cmark-gfm)](https://swiftpackageregistry.com/MarkCodable/swift-cmark) — the C parser under Apple's swift-markdown; GFM, fuzz-tested, safe HTML by default.

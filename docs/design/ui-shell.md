# UI Shell — design spec

Status: agreed Nov 1, 2026 (design session). Decisions: ADR-0005 (tabbed card shell with themes) and ADR-0006 (scroll sync). Mockup: open `docs/design/ui-shell-mockup.html` in a browser; the canvas source it was drawn from is in `docs/design/ui-shell-canvas/`. Work is tracked as phase **P5b — UI Shell** in the Build Plan.

Inspiration: Rex by Superlogical, for its tab strip, floating panes and themes. We take the *structure* and the *token shape*, not its assets or themes.

## 1. Window anatomy

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  ╭───────────────────────────────────────────────────────────╮  [⊟] [+]│  title bar, 52 pt
│        │ ▣ status-update.md  ✕ │ ▣ reply-to-priya.md • │ ▣ Untitled│          │  Tab strip
│        ╰───────────────────────────────────────────────────────────╯          │
│ ╭─ Editor Card ───────────────────────╮ ╭─ Preview Card ───────────────────╮ │
│ │ ✎ status-update.md  Markdown  ⊟ ⤢   │ │ 👁 Preview  [Copy as Rich Text ⌘C|▾] 🔗 ⤢ ✕│
│ │                                     │ │                                  │ │
│ │ # Weekly status — Payments          │ │ Weekly status — Payments         │ │
│ │ …                                   │ │ …                                │ │
│ │─────────────────────────────────────│ │──────────────────────────────────│ │
│ │ 64 words  Ln 7, Col 41        Saved │ │ Copies with [Headings −1] [Table │ │
│ ╰─────────────────────────────────────╯ ╰──────────────────────────────────╯ │
└──────────────────────────────────────────────────────────────────────────────┘
```

| Part | Size and spacing (pt) |
| --- | --- |
| Title bar | 52 tall; traffic lights at the system position; the strip starts after them (about 78 pt from the left edge) |
| Tab strip | One rounded container, radius 12, inset 3, background `strip`; fills the space between the traffic lights and the right-hand buttons |
| Tab | 32 tall, radius 9, max 210 wide and min 120; shrinks evenly when crowded, and scrolls horizontally after the minimum; 12.5 pt text; icon 14 |
| Right-hand title bar buttons | 30 × 30, radius 8: **Show Preview** (only while the Preview is hidden) and **New Tab (+)** |
| Card area | Padding 12 (top 2); gap 10 between Cards; this gap is the drag handle for the split |
| Card | Radius 12; background `card`; 1 pt `border` ring; `shadow` |
| Card header | 40 tall; 14 leading, 8 trailing; icon 16 tinted `accent`; title 13 pt semibold; icon buttons 28 × 28, radius 7, `muted` |
| Card footer | 28 tall; 11.5 pt `muted`; 1 pt `border` top rule |
| Editor text | SF Mono, 13 pt default, **line height 1.65**; horizontal padding 22 |
| Preview text | System font, the current `theme.css` sizes, **line height 1.6**; padding 6/30/20 |

The window is **opaque**: no vibrancy and no desktop showing through. The background is the theme's `windowGradient`, a 140° linear gradient from the first color to the second.

## 2. Tabs

One Tab is one Markdown document (a `DocumentGroup` document window inside the window's native tab group). See ADR-0005.

**Tab contents.** A document icon, the title, an **edited dot** (7 pt, `muted`) when the document has unsaved changes, and a close ✕ that shows on the active Tab and on hover.

- Active tab: background `tab`, `border` ring plus a small shadow, semibold, `foreground` text.
- Inactive tab: transparent, medium weight, `muted` text.

**Title.** For a saved document, the file name with its extension (`status-update.md`). For a document that has never been saved, the **suggested title** from its first non-blank line; "Untitled" when the document is empty. The rules are `DocumentTitle.suggested(from:)` in MarkdownCore:

1. Take the first line that isn't blank.
2. Strip leading block markers: `#`s, `>`, list bullets `- * +`, ordered markers `1.` `1)`, task boxes `[ ]` `[x]`, and the whitespace around them.
3. Remove inline emphasis and code markers (`*`, `_`, `~~`, backticks). Replace links `[text](url)` with `text`.
4. Collapse whitespace, then trim.
5. Truncate to 40 characters at a word boundary and add `…`.
6. If the result is empty, "Untitled".

The same title goes into `NSWindow.title`, so the Window menu and Mission Control match the strip. Saving switches the Tab to the file name.

**Keys and gestures**

| Action | Key or gesture |
| --- | --- |
| New Tab (an untitled document in this window) | ⌘T and ⌘N |
| Close Tab | ⌘W, or the ✕ (the normal save prompt and autosave rules apply) |
| Select tab 1–9 | ⌘1 … ⌘9 (⌘9 = last tab) |
| Next / previous tab | ⌃Tab / ⌃⇧Tab (the native "Show Next/Previous Tab") |
| Reorder | Drag a Tab within the strip |
| Move to a new window | Drag a Tab out of the strip, or Window ▸ Move Tab to New Window |
| Open from Finder or Open Recent | Opens as a new Tab in the front window |

## 3. Cards

There are always two Cards: **Editor** and **Preview**.

**Editor header:** a Markdown icon, the document title, a "Markdown" caption (`muted`), then the buttons:
- **Orientation**: side by side ↔ stacked. The icon shows the layout you'll switch *to*.
- **Maximize/Restore**.

**Preview header:** an eye icon and "Preview", then:
- **Copy split button** (§4).
- **Scroll sync toggle** (link icon; `accent` on a `strip` fill when on, `muted` when off).
- **Maximize/Restore**.
- **Hide Preview** (✕, ⇧⌘P).

**Behavior**
- **Orientation** is app-wide and remembered (`paneOrientation`: `sideBySide` | `stacked`, default `sideBySide`). Stacked puts the Editor above the Preview.
- **Split ratio** is app-wide and remembered (the existing `previewLeadingFraction`, clamped 0.2–0.8). Drag the gap between the Cards to change it. The cursor is resize left-right when side by side and resize up-down when stacked.
- **Maximize** shows one Card filling the Card area. It is temporary: not remembered, and reset when a window opens. Maximizing the Editor while the Preview is hidden is a no-op.
- **Hide Preview** removes the Preview Card, and the Editor fills the area. A **Show Preview** button appears in the title bar. ⇧⌘P toggles. This is remembered app-wide (the existing `showPreview`). The Editor can't be hidden.

**Editor footer:** `{words} words` · `Ln {line}, Col {column}` (the primary cursor, 1-based, columns counted in characters) · right-aligned save state: `Saved` / `Edited` / `Not saved` (never saved). Word count is `WordCount.count(in:)` in MarkdownCore. It counts whitespace-separated runs that contain at least one letter or digit, so Markdown markers alone don't count.

**Preview footer:** "Copies with" followed by three chips for the render options: **Headings −1** (Heading Demotion), **Table borders**, **Line breaks**. Each chip is a toggle bound to the same `UserDefaults` keys as Settings (`RenderSettings`):
- On: `strip` fill and `foreground` text.
- Off: no fill, `muted` text, and the label struck through.
- Changing a chip re-renders the Preview at once and changes what the next copy produces.

The right side of the footer shows "Scroll sync" or "Scroll sync off".

**Empty document**
- Editor: a `muted` hint, "Start typing Markdown. ⌘V turns rich text into Markdown."
- Preview: a centered `muted` line, "Your formatted text appears here."
- The Copy button is disabled.

## 4. Copy split button

The main action of the app, so it's the most visible control.

- **Main part:** a copy icon, **Copy as Rich Text**, and `⌘C` at 70% opacity. When the editor has a non-empty selection, the label reads **Copy Selection** and it copies the selection, exactly like ⌘C.
- **▾ part** (a 1 pt divider before it): opens a menu with Copy as Rich Text ⌘C, Copy as Markdown ⇧⌘C and Copy as HTML ⌥⌘C.
- **Colors:** `accent` fill, `onAccent` text (white on light themes, near-black on dark), height 28, radius 8.
- **Confirmation:** after *any* copy command for this document (button, menu or keyboard), the label changes for 1.4 s to a check and "Copied rich text" / "Copied Markdown" / "Copied HTML". The fill switches to the theme's `code` color, then reverts.
- The button calls the existing `CopyWriter` functions with the document's `CopySource`. No new copy logic.

## 5. Scroll sync

One-way, Editor → Preview, matched block by block. See ADR-0006 for the decision and the anchor format.

- `PreviewHTML` emits `data-source-line` on top-level blocks; `BareHTML` never does.
- `editor.js` posts `{type: "viewport", topLine}` (1-based) when the first visible line changes, at most once per animation frame.
- Swift forwards it to the Preview as `syncToLine(topLine)`. The Preview interpolates between the anchor at or above the line and the next anchor below it.
- After each `render(html)`, if sync is on, the Preview re-applies the last line.
- Off (the toggle) means the Preview keeps its own scroll position (today's behavior). App-wide, remembered (`scrollSync`, default on).

## 6. Themes

Each theme is a JSON file in `SkinnyDip/Resources/themes/`, in Rex's terminal token shape plus a `skinnyDip` block:

```json
{
  "id": "paper", "name": "Paper", "appearance": "light", "pair": "ink",
  "background": "#efe9df", "foreground": "#2b2b2b",
  "cursor": "#a84d26", "cursorText": "#efe9df",
  "selectionBackground": "#f0ddd2", "selectionForeground": "#2b2b2b",
  "ansi": ["… 16 colors …"],
  "skinnyDip": { "windowGradient": ["#efe9df", "#e4ecee"], "muted": "#67625c", "accent": "#a84d26" }
}
```

**Shipped set (four pairs):**

| Light | Dark |
| --- | --- |
| Paper | Ink |
| Sea Glass | Pine |
| Apricot | Ember |
| Lilac | Plum |

The default is **Match System** using Paper and Ink.

**Semantic roles.** `Theme.resolve()` in MarkdownCore maps each file to these roles. Anything the `skinnyDip` block leaves out is derived, so an imported terminal palette also works.

| Role | Source | Fallback when `skinnyDip` is absent |
| --- | --- | --- |
| `windowGradient` | `skinnyDip.windowGradient` | `[background, background]` |
| `foreground` | `foreground` | — |
| `muted` | `skinnyDip.muted` | a 62% foreground / 38% background mix |
| `accent` | `skinnyDip.accent` | `cursor` |
| `selection` | `selectionBackground` | — |
| `heading` | `ansi[4]` | — |
| `marker` (list and table punctuation, `#`, `>`, fences) | `ansi[8]` | — |
| `emphasis` (italic) | `ansi[5]` | — |
| `strong` | `foreground`, bold | — |
| `link` | `ansi[6]` | — |
| `code` (inline and fenced) | `ansi[2]` | — |
| `quote` | `muted`, italic | — |
| `onAccent` | `#ffffff` for light, `#121212` for dark | — |

**Surfaces depend only on appearance.** `Theme.resolve()` returns them too:

| Token | Light | Dark |
| --- | --- | --- |
| `card` | white 80% over the gradient | white 4.5% |
| `border` | black 8% | white 9% |
| `border2` (table rules, quote bar) | black 16% | white 22% |
| `strip` | black 5.5% | white 6% |
| `tab` (active) | white 95% | white 11% |
| `menu` | `#ffffff` | `#262a31` |
| `shadow` | `0 1 2 black 5%`, `0 8 24 black 6%` | `0 1 2 black 30%` |
| `codeBg` | black 5% | white 7% |

**Contrast.** The shipped themes were checked against `card`: every text role is at least 4.5:1 and `marker` at least 3:1. A unit test keeps it that way (MarkdownCore computes WCAG contrast).

**Where themes apply**

- Window gradient, Tab strip, Cards and menus: SwiftUI, from the resolved tokens.
- **Editor:** CodeMirror is themed through CSS variables that Swift sets with `window.setTheme(tokens)`, replacing today's `lightHighlight`/`darkHighlight` pair. The editor background is transparent, so the Card shows through.
- **Preview:** `theme.css` reads CSS variables (`--fg`, `--muted`, `--link`, `--border`, `--code-bg`, `--quote`), set with `window.setTheme(tokens)` in `preview.html`. The background is transparent. highlight.js colors in fenced code come from the same role colors.
- **Never the clipboard** (ADR-0001). Bare HTML has no colors.

**Picking a theme**
- **View ▸ Theme**: Match System, a separator, the four light themes, a separator, the four dark themes. A checkmark marks the current choice. Choosing a theme pins it (`themeMode = fixed`, `themeFixed = <id>`); choosing Match System sets `themeMode = system`.
- **Settings ▸ Appearance**:
  - "Light theme" and "Dark theme" pickers (`themeLight`, `themeDark`), used by Match System. Picking a light theme doesn't change the dark one, even though each light theme has a suggested partner.
  - Editor font size, a stepper from 10 to 24, default 13.
- Settings ▸ General keeps today's three render toggles.
- **⌘+ / ⌘− / ⌘0** (View menu) step the editor font size by 1 and reset it. Preview text scales by the same ratio. Remembered (`editorFontSize`).

## 7. Settings keys

| Key | Type | Default |
| --- | --- | --- |
| `showPreview` | Bool | true (exists) |
| `previewLeadingFraction` | Double | 0.5 (exists) |
| `paneOrientation` | String | `sideBySide` |
| `scrollSync` | Bool | true |
| `themeMode` | String | `system` |
| `themeFixed` | String | `paper` |
| `themeLight` | String | `paper` |
| `themeDark` | String | `ink` |
| `editorFontSize` | Double | 13 |
| `demotesHeadings`, `bordersTables`, `newlinesAsBreaks` | Bool | `RenderOptions.default` (exist) |

## 8. Out of scope here

- Two-way scroll sync.
- Window translucency.
- Theme import and editing.
- Font-family settings.
- More than two Cards.
- iPad and iPhone Tabs (P6).
- Changing the editor gutter. Line numbers are on today and the mockup omits them; that question is still open, and these issues leave the gutter as it is.

## 9. Issues

Parent: **P5b — UI Shell**. Children, in order:

1. Themes and floating Cards.
2. Tab strip (a spike, then the build).
3. Copy split button and Card footers.
4. Scroll sync.
5. Theme menu, Settings ▸ Appearance and font size.

The P2 paste-matrix gate (#7) comes before P5b.

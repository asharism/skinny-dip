# Editing Commands may insert Markdown syntax when the user asks

Amends ADR-0002. The Editor should feel like VS Code or Sublime Text to someone whose hands learned Markdown there (#88): Enter continues a list, Tab indents an item, ⌥↑ moves a line, ⌘B wraps a word. Each of these writes characters the user didn't type, which ADR-0002 read literally forbids. We allow them as **Editing Commands**: an edit the user explicitly asked for with a key or menu item (Enter on a list item, Tab, ⌘B, ⌥↑ and so on) that may insert or remove Markdown syntax on the lines the selection touches, in that moment only.

ADR-0002's point still holds: opening and saving a file changes nothing, and nothing rewrites text behind the user's back. A command is the user's own keystroke, so the change is theirs, it shows on screen at once, and ⌘Z takes it back.

The rules every Editing Command follows:
- **Only the lines the selection touches.** It never touches other lines: no renumbering of the following list items, no reformatting a table or a sibling item.
- **Only when asked.** Never on open, save, paste of our own copy, or a timer. No normalizing bullets, emphasis markers or numbering.
- **One undo step**, and undo restores both the text and the selection. A command that would change nothing declines and leaves no undo step.
- **Minimal edit.** It replaces only the span that changes, so spell-check marks, highlighting and the scroll position stay put.
- **Falls through when unsure.** Several selections, marked text (IME, dictation) and an active Writing Tools session get AppKit's default behavior.

How it's built: each command is a pure function `(EditorState) -> TextEdit?` in `MarkdownCore/MarkdownEditing`, in UTF-16 offsets, where `nil` means "not mine". The app only maps a key or menu item to the function and applies the edit through `NativeEditorTextView.apply(_:)`. Commands with a menu item live in the Format menu.

We considered and rejected:
- **Auto-format on save** (align tables, normalize bullets, fix numbering): it rewrites text the user didn't touch and wrecks diffs for files shared with VS Code, which is what ADR-0002 exists to prevent.
- **Renumbering the following ordered items** when one is inserted or removed: it edits lines the user didn't ask about. Markdown renders `1.`, `1.`, `1.` as 1, 2, 3 anyway, so the Preview and the paste are right without it.

Out of scope:
- **True multi-cursor.** `NSTextView` can hold several selections but can't type into them, and fighting TextKit for it isn't worth it. ⌘D "select next occurrence" may come later.
- **⌘/ toggle comment.** Bare HTML escapes raw HTML (ADR-0001), so `<!-- -->` would show as literal text in the Preview and in the paste.

## Consequences

- Every new command needs a paste-workflow reason, a MarkdownCore test table in caret notation (`EditFixture`), and a `NativeEditorTests` case that drives its real key.
- A few AppKit defaults change on purpose, such as ⌥↑/⌥↓ moving lines instead of jumping to the paragraph start. Each feature's PR records the keys it takes over.

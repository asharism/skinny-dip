# Editor spike scorecard

Issue #1. Each app opens the same 10,000-line document (`Shared/SampleDocument.swift`); its test bench at the top scripts every check. Score by hand: ✅ works as in TextEdit/Sublime, ⚠️ works with caveats (note them), ❌ missing or broken.

| Check | NSTextView | STTextView | CodeMirror 6 |
| --- | --- | --- | --- |
| Spell check (red underlines) |  |  |  |
| Autocorrect while typing |  |  |  |
| Dictation |  |  |  |
| Writing Tools: Rewrite / Proofread |  |  |  |
| ⌘D add next occurrence |  |  |  |
| ⌃⇧↑/↓ add cursor above/below |  |  |  |
| ⌘-click add cursor |  |  |  |
| Typing into all cursors |  |  |  |
| Typing feel at line 9,000 |  |  |  |
| Scroll smoothness, top to bottom |  |  |  |
| Undo / redo grouping |  |  |  |
| Memory, app (status bar) |  |  |  |
| Memory, WebContent (Activity Monitor) | n/a | n/a |  |

**Date / macOS / Xcode:**

**Verdict:**

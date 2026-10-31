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
| Typing feel at line 9,000 |  |  | ✅ no lag noticed |
| Scroll smoothness, top to bottom |  |  | ✅ |
| Undo / redo grouping |  |  |  |
| Memory, app (status bar) | 65 MB | 74 MB | 83 MB |
| Memory, WebContent + GPU + Networking | n/a | n/a | 147 + 19 + 5 MB (total ≈254 MB) |

**Date / macOS / Xcode:** 2026-10-31 / macOS 27.0 / Xcode 27.2. Memory measured with `footprint` after load, one document open. Rows left blank were not scored individually.

**Verdict:** CodeMirror 6 (ADR-0003). Spell check, dictation and Writing Tools were not scored row by row; verify them in the real app (P2).

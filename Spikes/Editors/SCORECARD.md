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

**Date / macOS / Xcode:** 2026-11-01 / macOS 27.0 / Xcode 27.2. Memory measured with `footprint` after load, one document open. Rows left blank were not scored individually.

### Real app (Skinny Dip, issue #6)

Accepted 2026-11-01 in the running Mac app. WebKit spell checking is turned on via `WebContinuousSpellCheckingEnabled`. Control keys are delivered through `keyDown` so CodeMirror sees them. Writing Tools uses the system submenu after the selection is expanded to full lines.

| Check | CodeMirror 6 (real app) |
| --- | --- |
| Spell check (red underlines) | ✅ |
| Autocorrect while typing | ✅ |
| Dictation | ✅ |
| Writing Tools: Rewrite / Proofread | ✅ context menu and Edit menu |
| ⌃⇧↑/↓ add cursor above/below | ✅ when Mission Control does not take the shortcut; ⌘⌥↑/↓ also adds a cursor |
| ⌃A, ⌃E, ⌃K | ✅ |

**Verdict:** CodeMirror 6 (ADR-0003). Issue #6 native-text checks are done.

### Native (real app, issue #64)

The native Editor Backend (`NSTextView` on TextKit 2, ADR-0010), picked under Settings › Advanced › Editor. Scored by an agent in the Debug agent build (`com.hitesh.SkinnyDipAgent1`) on 2026-11-11. The agent's terminal can't send keystrokes, dictation or clicks, so rows that need hands on the keyboard are left for a human. The existing CodeMirror column above stays as it was.

| Check | Native (real app) |
| --- | --- |
| Spell check (red underlines) | ✅ red underlines on misspellings in a restored Scratch Document (snapshot); `isContinuousSpellCheckingEnabled` on (`NativeEditorTests.smartQuotesOff`) |
| Autocorrect while typing | not verified (needs hands-on); the setting follows `NSSpellChecker.isAutomaticSpellingCorrectionEnabled` (test) |
| Smart quotes, dashes, text replacement | ✅ off (test), so the Markdown Source is never rewritten |
| Dictation | not verified (needs hands-on) |
| Writing Tools: Rewrite / Proofread | not verified (needs hands-on); `writingToolsBehavior = .complete` (test) |
| ⌃A, ⌃E, ⌃K | not verified (needs hands-on); AppKit text bindings, no workaround |
| Typing feel at line 9,000 | not verified (needs hands-on). Highlighting the 10,000-line sample (213k UTF-16 units, 13.9k spans) takes 85 ms in a Debug build and 27 ms in Release, off the main thread after a 120 ms pause |
| Scroll smoothness, top to bottom | not verified (needs hands-on) |
| Undo / redo grouping | ⚠️ paste is one undo step, and an outside text change is one undo step (`NativeEditorTests`); typing grouping is AppKit's own, not checked by hand |
| Multi-cursor | ❌ not supported (accepted in ADR-0010) |
| Memory, one document open (`footprint`, Debug build) | app 147 MB + WebContent 19 + GPU 10 + Networking 5 MB (total ≈ 181 MB) |
| Same build, CodeMirror selected | app 146 MB + WebContent 28 + 19 + GPU 11 + Networking 5 MB (total ≈ 209 MB) |

The native backend drops one WebContent process (the Editor's); the Preview still needs WebKit. Both builds were measured right after launch with the same one-paragraph document, so these numbers say nothing about growth over a long run (#62 soak).

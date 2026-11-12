# Trial a native NSTextView editor behind a setting, then keep one

ADR-0003 chose CodeMirror 6 in a `WKWebView`. After a few weeks of daily use, the user finds it slow, and memory seems to grow when Skinny runs for a long time. We're adding a second **Editor Backend**: AppKit `NSTextView` on TextKit 2, the setup that Silica (dqhieu/Silica, MIT) uses. The user picks it under Settings › Advanced › Editor, and switching relaunches the app. After a trial with measurements and a week of daily use, we keep **one** backend and delete the other. Shipping several editors as a permanent option is not the goal.

The choice rests on numbers we already have and some we still need:
- **Memory.** The issue #1 spikes measured about 65 MB for `NSTextView` against about 254 MB for CodeMirror (the app plus WebContent, GPU and Networking). The Preview still needs a web view, so the native editor removes one WebContent process, not all of WebKit.
- **Long-running growth is still unexplained.** CodeMirror's undo history is not the cause. A Node measurement (2026-11-11) showed `exportState()` levels off at about 1.3 MB and about 4 ms once it reaches the 10,000-step cap. It does run for every Scratch Document after each pause in typing (`ContentView.noteScratchEdit`), which is wasted work but has a ceiling. Before we compare backends, a soak harness measures where the growth actually is: the Editor web view, the Preview web view, or the app.

STTextView is still rejected. It's GPL-3.0 or paid, and shipping it would make the distributed MIT app GPL-3.0 in practice. We only reconsider it if `NSTextView` falls short on something STTextView fixes.

## Consequences

- **One seam, two backends.** The shell, copy, paste, Writing Tools, menu routing and scroll sync talk to an `EditorBackend` abstraction, never to `EditorWebView` directly. The rest of the app doesn't know which editor is running.
- **No multi-cursor in the native backend.** `NSTextView` can't hold several empty carets (ADR-0003). We accept that for the trial.
- **No undo history across launches in the native backend.** `NSUndoManager` can't be serialized, so in the native backend Scratch Documents restore their text but not their undo stack. That breaks the "restored with their undo history" part of ADR-0007 for as long as the native backend is selected. Undo within a session works normally.
- **Switching backends discards undo history.** Settings warns about this, then relaunches. Scratch Document text, files and Tabs carry over. Saved history is tagged with the backend that wrote it, and the other backend ignores it.
- **Markdown highlighting in the native backend comes from MarkdownCore.** It uses `swift-markdown`'s source ranges, parsed off the main thread, and sets only the foreground color, so highlighting never adds undo steps or marks the document as edited. It doesn't use a regex grammar.
- **Spell check, autocorrect, dictation and Writing Tools come from AppKit** in the native backend, so it needs none of the issue #6 WebKit workarounds.
- When the trial ends, the losing backend, its code and its tests are deleted, and this ADR records the result.

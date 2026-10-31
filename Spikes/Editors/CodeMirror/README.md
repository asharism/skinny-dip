# CodeMirror spike

[CodeMirror 6](https://codemirror.net) (MIT) in a `WKWebView`, wrapped in an `NSViewRepresentable`. One of three editor-evaluation apps for issue #1; see `../README.md` and `../SCORECARD.md`.

## Run

```sh
xcodegen generate
xcodebuild build -scheme CodeMirrorSpike -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode
open .build/xcode/Build/Products/Debug/CodeMirrorSpike.app
```

Run the binary directly (`.build/xcode/Build/Products/Debug/CodeMirrorSpike.app/Contents/MacOS/CodeMirrorSpike`) to see JS messages on stdout, such as `documentLoaded` with line count and load time. Web Inspector is on: Safari → Develop → this Mac → CodeMirror spike. `window.editorView` is the live `EditorView`.

## Rebuild the JS bundle

`Resources/editor.bundle.js` is prebuilt and checked in, so the app builds without Node. After changing `web/src/editor.js` or the versions in `web/package.json`:

```sh
cd web && npm install && ./build.sh
```

Then rebuild the app.

## What is set up

- `basicSetup`, Markdown with GFM (`markdownLanguage`), line wrapping, multiple selections, rectangular selection (⌥-drag).
- Content attributes `spellcheck`, `autocorrect`, `autocapitalize` and `writingsuggestions` are turned on (CM turns them off by default). `writingToolsBehavior = .complete` on the web view configuration.
- Keys: ⌘D next occurrence, ⌘-click add cursor, ⌘⌥↑/↓ add cursor above/below (all CM defaults on macOS). ⌃⇧↑/↓ is added for the Sublime habit; it overrides CM's macOS default of select page up/down.
- Fills the window, monospaced font, light/dark from `prefers-color-scheme`.
- No `@codemirror/language-data`, so fenced code blocks are not syntax-highlighted inside.

## Native behavior: bridged or not

| Behavior | State in this spike |
| --- | --- |
| Loading the document | Bridged: Swift calls `setDocument(text)` with `callAsyncJavaScript` after load |
| Spell check, autocorrect, Writing Tools, dictation | Left to WebKit; score them |
| Undo / redo | Not bridged. Stays in CM's `history`; no `NSUndoManager`, so the Edit menu's Undo item may not reflect it |
| NSDocument, dirty state, saving | None. The document is not saved |
| Find | System Find bar not wired. ⌘F opens CM's own search panel |
| Select All | Not bridged. CM's ⌘A handles it; the Edit menu item goes to WebKit, which may select only the rendered viewport |
| Memory | The status bar shows the app process only. Read the WebContent process in Activity Monitor |

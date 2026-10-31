# STTextView spike

Evaluation app for issue #1: [STTextView](https://github.com/krzyzanowskim/STTextView) 2.4.1 (TextKit 2, AppKit) in a SwiftUI window, loading the shared 10,000-line document. Score it with `../SCORECARD.md`.

## Run

```sh
cd Spikes/Editors/STTextView
xcodegen generate
xcodebuild build -scheme STTextViewSpike -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode
open .build/xcode/Build/Products/Debug/STTextViewSpike.app
```

Or `open STTextViewSpike.xcodeproj` and press ⌘R.

## License

STTextView is **GPL-3.0 or a paid commercial license** ([LICENSE](https://github.com/krzyzanowskim/STTextView/blob/main/LICENSE.md)). This spike is for local evaluation only. Shipping Skinny Dip on STTextView needs the commercial license (or a GPL app). The app only calls STTextView's API; no STTextView source is copied in.

## What is turned on

Set in `Sources/Editor.swift`: monospaced 13 pt font, soft wrap (`isHorizontallyResizable = false`), undo, find bar (⌘F, incremental), current-line highlight, continuous spell check, grammar check, automatic spelling correction, text replacement, text completion. Smart quotes are off.

STTextView has no Writing Tools switch. It adopts `NSServicesMenuRequestor`, so Writing Tools may appear in the context menu or Edit menu; whether Rewrite/Proofread works is a scorecard check.

## Multi-cursor

| Gesture | Source |
| --- | --- |
| ⌃⇧-click: add caret | Native (`STTextView+Mouse.swift`) |
| ⌥-drag: visual (column) selection | Native |
| Typing, deleting and arrow keys on all carets | Native |
| ⌘-click: add caret | Wired here (`Sources/SpikeTextView.swift`) |
| ⌘D: select word, then add next occurrence (wraps) | Wired here |
| ⌃⇧↑ / ⌃⇧↓: add caret above the top caret / below the bottom one | Wired here |

STTextView has no built-in add-next-occurrence or add-caret-above/below. The wired gestures live in a `STTextView` subclass. They set `textLayoutManager.textSelections` with Apple's public `NSTextSelectionNavigation` API, then ask the view to redraw. ⌘-click needs `contentFrame`, which STTextView marks `@_spi(Plugins)`, so that file uses `@_spi(Plugins) import STTextView`.

Overriding ⌘-click replaces whatever STTextView would do for a plain ⌘-click.

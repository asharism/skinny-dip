# Editor spikes

Evaluation apps for issue #1: which engine should Skinny Dip's Mac editor use? They are kept, not thrown away, so the comparison can be re-run when an engine, macOS or Xcode changes. They are not product code: nothing in `SkinnyDip/` or `Packages/` depends on them.

| App | Engine | License |
| --- | --- | --- |
| `NSTextView/` | Apple's `NSTextView` (TextKit 2), no add-ons | Apple SDK |
| `STTextView/` | [STTextView](https://github.com/krzyzanowskim/STTextView) | GPL-3.0 or commercial |
| `CodeMirror/` | [CodeMirror 6](https://codemirror.net) in a `WKWebView` | MIT |

Every app opens the same 10,000-line document from `Shared/SampleDocument.swift` and shows its memory footprint in a status bar (`Shared/`). Score them with `SCORECARD.md`; background research is in `docs/research/editor-engines.md`.

## Run one

```sh
cd Spikes/Editors/<App>
xcodegen generate
open <App>Spike.xcodeproj   # then ⌘R, or:
xcodebuild build -scheme <App>Spike -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode
```

Each app's own README covers anything extra (CodeMirror's JS bundle is prebuilt and checked in; rebuilding it needs Node).

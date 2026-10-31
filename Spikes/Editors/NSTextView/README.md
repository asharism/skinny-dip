# NSTextView spike

The baseline: Apple's `NSTextView` on TextKit 2, with no third-party code. It opens the shared 10,000-line document (`../Shared/SampleDocument.swift`), and the status bar shows app memory. Score it with `../SCORECARD.md`.

## Run

```sh
cd Spikes/Editors/NSTextView
xcodegen generate
xcodebuild build -scheme NSTextViewSpike -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/xcode
open .build/xcode/Build/Products/Debug/NSTextViewSpike.app
```

Or open `NSTextViewSpike.xcodeproj` and press ⌘R.

## What's in it

All of it is in `Sources/Editor.swift`, an `NSViewRepresentable` around `NSTextView.scrollableTextView()`. On launch it checks `textLayoutManager != nil`, so it stops if it ever falls back to TextKit 1.

| Setting | Value |
| --- | --- |
| Text | Plain text (`isRichText = false`), 13 pt monospaced system font, soft wrap to the view width |
| Undo | `allowsUndo` |
| Find | `usesFindBar`, `isIncrementalSearchingEnabled` |
| Spelling and grammar | `isContinuousSpellCheckingEnabled`, `isGrammarCheckingEnabled`, `isAutomaticSpellingCorrectionEnabled` |
| Text replacement and completion | `isAutomaticTextReplacementEnabled`, `isAutomaticTextCompletionEnabled`, `inlinePredictionType = .yes` |
| Writing Tools | `writingToolsBehavior = .complete` |
| Off (they would rewrite Markdown) | Smart quotes, smart dashes, link detection, data detection, smart insert/delete |

Dictation, Services and the Edit menu's spelling and substitution items come from AppKit without any code.

## Multi-cursor: native vs. absent

There is no multi-caret layer on purpose. This column of the scorecard measures what AppKit does on its own.

- **Native:** discontiguous selection with ⌘-drag, and rectangular (column) selection with ⌥-drag. Typing replaces the selected ranges with one insertion. It does not type into each range.
- **⌘D:** NSTextView has no binding for it, and the SwiftUI app menu has no ⌘D item, so nothing happens (or it beeps). There is no "select next occurrence".
- **⌃⇧↑ / ⌃⇧↓:** there is no "add cursor above/below" command. The keys either do nothing or fall through to a selection-extending binding or a system shortcut (Mission Control uses ⌃↑/⌃↓). Note what you see when you score it.
- **⌘-click:** this does not add a caret. `selectedRanges` cannot hold more than one empty range, so a ⌘-click with no drag adds nothing.

To get Sublime-style multi-cursor here, you would have to build it on top of NSTextView: draw the extra carets yourself and fan out each edit.

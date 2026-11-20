---
name: drive-app
description: Check a change in the running Skinny app, screenshot the app, run the app and exercise menus, shortcuts or editor commands. Use before handing back any editor, menu or keyboard-shortcut change.
---

# Drive the running app

Run a JSON step script inside the Debug agent build and read back what happened. The app runs the steps itself on its front document's editor, so menus and key equivalents genuinely reach it (outside keyboard events and osascript menu clicks do not).

```sh
scripts/drive.sh steps.json
```

The script builds `.build/agent` under `com.hitesh.SkinnyDipAgent` (never the real bundle ID), launches it with empty Scratch Documents, prints the result JSON, quits the app, and exits non-zero if any step failed. `--no-build` reuses the last build; `--keep-open` leaves the app running. The result also lands beside your steps file as `<name>.result.json`.

## Steps

`{"steps": [...], "quit": true}` (or a bare array). Steps run in order.

| step | fields | does |
|---|---|---|
| `setText` | `text` | replaces the document through `insertText`, caret at the end |
| `select` | `location`, `length` | sets the selection (UTF-16 offsets) |
| `menu` | `menu`, `item` | performs the real main-menu item with the editor focused; fails if missing or disabled |
| `key` | `key`, `modifiers` | key down via window key equivalents, then main menu, then the first responder. `key` is a character or `up down left right return tab escape delete space`; modifiers `command shift option control` |
| `selector` | `selector` | `NSApp.sendAction` down the responder chain, e.g. `"selectLine:"` |
| `setPasteboard` | `text` | writes the general pasteboard; the previous string returns when the script ends |
| `focusEditor`, `focusPreview` | | moves first responder (Preview must be visible) |
| `wait` | `ms` | sleeps |
| `snapshot` | `path` | PNG of the window; the path must sit inside `~/Library/Containers/com.hitesh.SkinnyDipAgent/Data/tmp/` |
| `dumpText` | | records state only |

Every step's result carries `ok`, `error`, `note` (which dispatch path ran), and the editor `text`, `selection` `[location, length]`, `keyWindow` and `firstResponder` after it.

## Example

```json
{"quit": true, "steps": [
  {"step": "setText", "text": "a word b"},
  {"step": "select", "location": 2, "length": 4},
  {"step": "menu", "menu": "Format", "item": "Bold"},
  {"step": "key", "key": "i", "modifiers": ["command"]},
  {"step": "snapshot", "path": "/Users/<you>/Library/Containers/com.hitesh.SkinnyDipAgent/Data/tmp/bold.png"}
]}
```

Read the `text` of the `menu` step: `"a **word** b"` means the menu path worked. Compare it to the text you expect, and read the snapshot PNG with the Read tool to check rendering.

## Verify like this

- Assert on the result's `text` and `selection`, not on `ok` alone: `ok` means the step ran, not that the feature behaved.
- Exercise both paths of a shortcut: the `menu` step and the `key` step.
- `keyWindow: false` or a `firstResponder` other than `NativeEditorTextView` means the menu validated against the wrong target; fix the script before trusting the result.

## Limits

- No real keyboard: `key` builds an `NSEvent` and dispatches it in-process; text-input paths like dead keys, IME and key repeat are not covered.
- No Writing Tools UI, no live dictation, no system dialogs.
- The Preview takes focus but gets no clicks or drags; use CGEvent mouse drags from outside for those.
- Debug builds only: the hook is `#if DEBUG` (`SkinnyDip/Platform/DebugDrive+Mac.swift`).

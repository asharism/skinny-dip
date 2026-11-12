# Editor soak harness

Measures memory and typing latency over a long session (#62), so the Editor Backends can be compared on the same script (ADR-0010). The CodeMirror baseline is below; #64 adds the native column.

## How it works

- **In-app driver** (`SkinnyDip/Platform/DebugSoak+Mac.swift`, Debug code only). Synthetic keyboard input from a terminal doesn't reach the app without Accessibility permission, so the app types into itself. It opens 3 Tabs, then types `SoakScript` text (headings, bullet and numbered lists, a task, a table, a code fence, a quote, links, inline code and emphasis) at 8 characters per second with a 1.2 s pause every 40 characters. Each minute it moves on to the next Tab. After the typing phase it sits idle.
- Each character is one user-input transaction through `DebugTypingTarget`: in CodeMirror, `debugType` in `editor.js` dispatches with `userEvent: "input.type"`. Undo history, the document binding, Preview rendering and the Scratch Document flush (with `exportState()`) all run as they do for a person.
- **Typing latency** is the time from dispatch until `EditorController` hears the change (`debugTextObserver`). For CodeMirror that covers the JS transaction, the `documentChanged` message and the wait for the app's main thread.
- **Sampler** (`scripts/soak.sh`): builds Release with the `DEBUG` condition (so the driver is compiled in and Sparkle stays off), clears Scratch Documents and saved windows in the test bundle's container, launches with `open -n -F`, and every 30 s writes the `footprint` of the app and each WebKit helper to a CSV. Helpers are the WebKit processes that appeared since launch (`pgrep -f com.apple.WebKit` before and after). The driver also reports which WebContent process belongs to which Tab's Editor or Preview, plus the GPU and Networking process IDs, so columns are labelled and helpers from other apps that started at the same moment are dropped.

## Running it

Never with the real bundle ID (the script refuses `com.hitesh.SkinnyDip`): the test bundle has its own sandbox container, so the user's Scratch Documents are never touched.

```sh
scripts/soak.sh 30                                   # baseline: 30 min typing, 10 idle
scripts/soak.sh 30 SKINNYDIP_SOAK_NO_PREVIEW=1       # no Preview web view, no Preview rendering
scripts/soak.sh 30 SKINNYDIP_SOAK_NO_HISTORY_EXPORT=1  # Scratch flush skips exportState()
scripts/soak.sh 1 --idle 1 --interval 10 --label smoke  # quick check
# options: --bundle-id (default com.hitesh.SkinnyDipAgent), --derived-data (default .build/agent),
#          --idle <min>, --interval <s>, --label <name>, --no-build
```

Output goes to `.build/soak/<timestamp>-<label>.csv` (MB per process), `.json` (the driver's log: per-minute latency, process IDs) and `.summary.txt` (`scripts/soak-summary.py`). Other app env switches: `SKINNYDIP_SOAK_TABS` (3), `SKINNYDIP_SOAK_SEED` (1). The window opens on screen; leave it alone during the run.

## CodeMirror baseline

Measured 2026-11-12 on a Mac17,7 (macOS 27.0), Release build with the `DEBUG` condition, 3 Tabs, 30 min typing (about 11,650 characters, so about 3,900 per Tab) plus 10 min idle. `footprint` in MB. Each Tab gets typed into for one minute in three, so a Tab's growth comes from about 10 minutes of its own typing.

Each cell is the value when typing starts → at the end of typing → at the end of idle. Editor and Preview cells show the range across the 3 Tabs.

| Process | Baseline | No Preview | No history export |
| --- | --- | --- | --- |
| App | 61 → 65 → 65 | 60 → 84 → 83 | 61 → 82 → 82 |
| Editor WebContent (each Tab) | 27–31 → 119–133 → 119–134 | 33–38 → 116–170 → 116–140 | 27–32 → 97–118 → 97–118 |
| Preview WebContent (each Tab) | 19–20 → 51–66 → 51–66 | none | 19–20 → 44–48 → 44–49 |
| GPU | 191 → 240 → 45 | 206 → 215 → 37 | 207 → 51 → 40 |
| Networking | 6 → 5 → 5 | 5 → 5 → 5 | 6 → 5 → 5 |
| **Total** | **402 → 874 → 680** | **375 → 712 → 504** | **418 → 609 → 599** |

GPU is noisy within the typing phase (it swings between about 40 and 250 MB depending on when the sample lands). That's why the no-history run's end-of-typing value is low. Everything it gains while typing comes back once the app goes idle.

Typing latency (dispatch until `EditorController` hears the change), in ms:

| | p50 | p95 | max | p95, first 6 min → last 6 min (median) |
| --- | --- | --- | --- | --- |
| Baseline | 3.3 | 12.9 | 56.0 | 12.9 → 15.2 |
| No Preview | 3.8 | 6.4 | 34.4 | 4.7 → 7.1 |
| No history export | 3.8 | 6.0 | 27.6 | 4.6 → 6.2 |

### What it shows

- **The growth is in the Editor's WebContent process.** Each Editor grows by about 70–135 MB over about 3,900 typed characters (roughly 20–25 KB per character). It doesn't come back after 10 idle minutes. Hiding the Preview doesn't change it, and neither does skipping `exportState()` on every pause. So neither the Preview nor the history export causes it. What's left is the typing path inside the Editor process: CodeMirror's state, history and DOM, plus the `documentChanged` message, which posts the whole document on every keystroke. This harness can't tell those apart.
- **The Preview's WebContent grows too**, by about 25–45 MB per Tab, and doesn't come back when idle.
- **GPU memory is a cache.** It climbs to about 240 MB while typing and falls to about 40 MB when idle.
- **The app process is flat** (about 60–85 MB).
- **Latency is low.** p50 is about 3–4 ms and p95 under 16 ms. The baseline's p95 is about twice that of either attribution run, so Preview rendering and the history export both cost main-thread time while typing. The baseline's p95 also creeps up over the run.

## Native backend

#64 adds its column here, measured with the same script.

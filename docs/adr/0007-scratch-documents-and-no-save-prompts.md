# Scratch documents, and no save prompts

Skinny never asks "Do you want to save?". Saved files autosave in place, which is `DocumentGroup`'s default. Documents the user never saved are **Scratch Documents**: Skinny stores them in its own Application Support folder, writes them a second after each edit, and reopens every one of them as a Tab on launch, together with its undo history. Closing a non-empty Scratch Document's Tab moves it to **Recently Closed** (kept 30 days, reopened with ⇧⌘T) instead of prompting. Details are in `docs/design/ui-shell.md` §8.

macOS already autosaves untitled documents, but it falls short in two ways. Closing one still asks "Save or delete?". And whether untitled documents come back after quitting depends on a system-wide setting ("Close windows when quitting an application") the app doesn't control. Skinny is a scratchpad, so drafts that vanish or nag defeat its purpose. We rejected always prompting (the macOS default), and also no-prompt without Recently Closed, where one misclick on ✕ loses a draft for good.

Undo keeps at least 10,000 steps. Scratch Documents persist their CodeMirror history alongside the text, so "comes back exactly as I left it" includes ⌘Z. Saved files keep history in memory only, because a file can change outside the app (VS Code, git), which would make a stored history lie.

## Consequences

- A Scratch Document still opens as an ordinary untitled `DocumentGroup` document; only its storage and lifecycle are ours. Saving it with ⌘S turns it into a normal file and deletes its scratch copy.
- The untitled-on-launch behavior (P2) runs only when no Scratch Documents were restored.
- Scratch storage is plain `.md` files plus a JSON sidecar. If the app breaks, the user can still recover the text from Finder.
- Recently Closed holds at most 20 visible entries, and files older than 30 days are deleted on launch, so storage stays bounded.

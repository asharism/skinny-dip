# Tabbed card shell with themes, styled after Rex

Skinny Dip's window takes its look from Rex (Superlogical): a capsule **Tab** strip in the title bar, the Editor and Preview as floating rounded **Cards** on a tinted window, and a **Theme** that tints everything. One Tab is one Markdown document. The design is in `docs/design/ui-shell.md` and the mockup in `docs/design/ui-shell-mockup.html`.

This moves custom themes and tabs off the MVP "Out" list, each with a paste-workflow reason. With Tabs, several drafts (a reply, a status update, meeting notes) stay open in one window instead of a pile of windows. Themes make the app pleasant enough to leave open, which is the success metric ("you stop opening VS Code").

**Tabs stay on `DocumentGroup`.** Each Tab is still a real document window in a native macOS window tab group. We hide the native tab bar and draw our own strip from `NSWindow.tabGroup` (`windows`, `selectedWindow`). Autosave, versions, recents, Finder open, the edited state and state restoration all stay free. We rejected a single window that manages its own documents, because it means rebuilding all of that by hand. If the spike shows the custom strip can't be made to work (flicker, focus, ordering), we fall back to the native tab bar with themed Cards, never to a hand-rolled document manager.

**Themes are our own, in Rex's token shape.** Each theme file uses the terminal palette shape (background, foreground, cursor, selection and 16 ANSI colors) plus a small `skinnyDip` block (window gradient, muted, accent). We ship four light/dark pairs that we designed ourselves. Rex's themes are Superlogical's work and are not copied. Because we use the same shape, terminal palettes (Ghostty, iTerm) could be imported later.

## Consequences

- The clipboard is never themed. Themes reach the window, the Cards, the Editor's syntax colors and the Preview only (ADR-0001 is unchanged).
- The window is opaque, with no translucency: text contrast and a Preview that resembles the paste destination win over the Rex glass look.
- The layout is fixed at two Cards, Editor and Preview. They can sit side by side or stacked, either can be maximized, and the Preview can be hidden. There is no arbitrary splitting.
- iPad and iPhone (P6) don't get the Tab strip yet. `SplitPane` and the Cards carry over, and the Tab design for iPad is decided in P6.

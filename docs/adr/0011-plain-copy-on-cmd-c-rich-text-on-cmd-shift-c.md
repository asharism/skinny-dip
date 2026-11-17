# Plain Copy on ⌘C, Copy as Rich Text on ⌘⇧C

Until now ⌘C was Copy as Rich Text, because pasting into Outlook and Teams is what Skinny is for. After a few days of daily use the user wants ⌘C to behave as it does in every other Mac editor: copy the selected text, as text. ⌘C is the most reflexive key on the Mac, and a quick copy of a snippet that arrives as HTML gets turned into formatting by apps that prefer HTML (Slack, Notes, Teams chat, GitHub web fields). The rich copy is a deliberate act (finish the note, send it), so it can afford a modifier.

| Shortcut | Command | With a selection | With no selection |
|---|---|---|---|
| ⌘C | Copy (standard) | the selected Markdown, `public.utf8-plain-text` only | nothing; the menu item is disabled |
| ⌘⇧C | Copy as Rich Text | Bare HTML + Markdown of the selection | the whole document |
| ⌥⌘C | Copy as HTML | the selection's HTML as plain text | the whole document |

- **Same keys in both Cards.** In the Preview, a selection still widens to the Markdown Source of the blocks it touches (`PreviewSelection`); ⌘C copies that Markdown as plain text and ⌘⇧C copies it as rich text. We never use WebKit's styled copy.
- **⌘C does nothing with no selection.** It's the standard Copy, and copying the whole file on a reflexive ⌘C would silently overwrite the clipboard. The whole-document fallback stays on ⌘⇧C and ⌥⌘C, where copying the whole note is the point.
- **Copy as Markdown leaves the Edit menu.** ⌘C now does its job for a selection. It stays in the Copy split button's ▾ menu, with no shortcut shown, for copying the whole document's source.
- **The Copy split button stays rich.** Clicking it is still Copy as Rich Text, so the main workflow is one click or ⌘⇧C.
- The change sits above the Editor Backend seam, so both backends get it. Pasting our own copy back into Skinny still uses the Markdown flavor.

We considered keeping ⌘C rich and adding a plain shortcut instead. We rejected it: every other Mac text app trained the user's hands, and the surprise was the reflexive ⌘C, not the lack of a plain-copy key.

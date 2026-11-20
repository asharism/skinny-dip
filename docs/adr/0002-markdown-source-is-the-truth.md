# Markdown Source is the truth; no WYSIWYG editing

Skinny edits the Markdown Source directly and never rewrites a character the user didn't type, so opening and saving a file changes nothing. We considered a Notes-style editor (rich text on screen, Markdown underneath) and rejected it: every WYSIWYG engine we found (ProseMirror, Tiptap, Milkdown, Lexical) normalizes the source on save (emphasis markers, bullets, reference links, hard breaks), which wrecks git diffs for files shared with VS Code, and none supports the Sublime-style multi-cursor the user relies on. Styled-in-place "live preview" (Obsidian/Typora) stays possible later because it decorates the source rather than replacing it. Evidence: `docs/research/editor-engines.md`.

Amended by ADR-0012: an Editing Command the user asks for with a key or menu item (Enter on a list item, Tab, ⌘B) may insert or remove Markdown syntax on the lines the selection touches. Nothing changes on open or save.

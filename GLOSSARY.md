# Skinny

A Markdown scratchpad whose job is to turn Markdown into rich text that pastes cleanly into other apps.

## Writing

**Markdown Source**:
A document's text exactly as the user typed it; the source of truth that Skinny never rewrites on its own.
_Avoid_: raw text, plain text, model

**Preview**:
The live rendering of the Markdown Source in its own Card, showing the structure Copy as Rich Text will paste, in Skinny's own theme rather than the destination's.
_Avoid_: viewer, render pane

## Window

**Tab**:
One open Markdown document in the window's Tab strip; each Tab has its own Editor and Preview Cards.
_Avoid_: window, pane, workspace

**Card**:
One of the two floating rounded panels in a Tab, the Editor Card or the Preview Card, each with a header and a footer.
_Avoid_: pane, panel, block

**Theme**:
A named palette (window tint, text, accent, syntax colors) applied to the window, the Cards, the Editor and the Preview, never to the clipboard; themes come in light/dark pairs.
_Avoid_: skin, color scheme

**Zoom**:
The single scale factor (⌘+ / ⌘− / ⌘0) applied to the whole window: Tab strip, Cards, Editor and Preview.
_Avoid_: font size, text size

**Scroll Sync**:
The Preview following the Editor's scroll position, block by block; one-way, Editor to Preview.
_Avoid_: linked scrolling

## Documents

**Scratch Document**:
A document the user has never saved to a location of their choosing; Skinny stores it itself, with its undo history, and reopens it on launch.
_Avoid_: untitled file, temp file, draft

**Recently Closed**:
The list of Scratch Documents whose Tabs were closed in the last 30 days, reopened with ⇧⌘T.
_Avoid_: trash, history

**Duplicate**:
Opening an unsaved copy of the current document as a new Scratch Document in the next Tab.

## Copying out

**Bare HTML**:
Semantic HTML carrying structure only (headings, paragraphs, lists, emphasis, links, quotes, tables, code), with no fonts, colors or styling of any kind.
_Avoid_: clean HTML, inlined HTML, styled HTML

**Copy as Rich Text**:
The command that puts a document or selection on the clipboard as Bare HTML plus its Markdown source, so it pastes as formatted text that takes on the destination's own styling.
_Avoid_: Copy for pasting, rich copy, Outlook copy

**Copy as HTML**:
The command that puts the Bare HTML on the clipboard as plain text, for pasting HTML source somewhere.
_Avoid_: Copy HTML source

**Copy as Markdown**:
The command that puts only the Markdown source on the clipboard, for when the source itself should land in a rich app.
_Avoid_: plain copy, Copy

**Heading Demotion**:
Shifting every heading down one level on copy so a document's top heading doesn't dominate an email; the lowest level stays where it is.

**Selection Copy**:
A copy of only the selected part of a document, rendered as if the selection were a document of its own.
_Avoid_: partial copy

## Destinations

**Paste Target**:
A destination app that Skinny output is pasted into and checked against by hand each release (Outlook, Word, Gmail, Teams and so on).
_Avoid_: client, destination app, target

**Tier 1 Paste Target**:
A Paste Target where a broken paste blocks a release: new Outlook, Outlook for Mac, Teams. Wins when targets disagree on a default.

**Tier 2 Paste Target**:
A Paste Target fixed when cheap, where a known defect can ship: Word, Gmail web, Apple Mail, Google Docs.

## Bringing text in

**Paste as Markdown**:
Pasting rich text from another app into the editor as its Markdown equivalent.
_Avoid_: import, HTML paste

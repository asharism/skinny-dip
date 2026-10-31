// CodeMirror 6 editor for the Skinny Dip CodeMirror spike.
// Bundled by build.sh into ../Resources/editor.bundle.js and loaded by editor.html.
import { basicSetup } from "codemirror";
import { EditorView, keymap, rectangularSelection } from "@codemirror/view";
import { EditorState, Compartment, Prec } from "@codemirror/state";
import { addCursorAbove, addCursorBelow } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

// Post to the Swift side (WKScriptMessageHandler "spike"); no-op in a plain browser.
function post(message) {
  try {
    window.webkit?.messageHandlers?.spike?.postMessage(message);
  } catch (_) {}
}

// Sublime habits. Mod-d (selectNextOccurrence) and Mod-click (add cursor) are
// CodeMirror defaults on macOS; Cmd-Alt-Up/Down also add cursors by default.
// Ctrl-Shift-Up/Down are added here; on macOS CM binds them to selectPageUp/Down,
// so this keymap takes precedence.
const sublimeKeys = Prec.highest(
  keymap.of([
    { key: "Ctrl-Shift-ArrowUp", run: addCursorAbove, preventDefault: true },
    { key: "Ctrl-Shift-ArrowDown", run: addCursorBelow, preventDefault: true },
  ]),
);

const darkHighlight = HighlightStyle.define([
  { tag: t.heading, fontWeight: "bold", color: "#7cb7ff" },
  { tag: [t.strong], fontWeight: "bold" },
  { tag: [t.emphasis], fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: [t.link, t.url], color: "#8fd3ff", textDecoration: "underline" },
  { tag: [t.monospace], color: "#e6b673" },
  { tag: [t.keyword, t.processingInstruction], color: "#c792ea" },
  { tag: [t.string], color: "#c3e88d" },
  { tag: [t.number, t.atom, t.bool], color: "#f78c6c" },
  { tag: [t.comment, t.meta, t.contentSeparator, t.quote], color: "#8a93a5" },
  { tag: [t.list], color: "#d0d0d0" },
]);

const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
const highlight = new Compartment();
const highlightFor = (dark) => (dark ? syntaxHighlighting(darkHighlight) : []);

const baseTheme = EditorView.theme({
  "&": { height: "100%" },
  ".cm-scroller": {
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace",
    fontSize: "13px",
    lineHeight: "1.5",
  },
});

function extensions() {
  return [
    sublimeKeys,
    basicSetup,
    markdown({ base: markdownLanguage }), // GFM: tables, task lists, strikethrough, autolinks
    EditorView.lineWrapping,
    EditorState.allowMultipleSelections.of(true),
    rectangularSelection(), // also in basicSetup; explicit so the spike's intent is visible
    EditorView.contentAttributes.of({
      spellcheck: "true",
      autocorrect: "on",
      autocapitalize: "on",
      writingsuggestions: "true",
    }),
    baseTheme,
    highlight.of(highlightFor(darkQuery.matches)),
  ];
}

const view = new EditorView({
  state: EditorState.create({ doc: "", extensions: extensions() }),
  parent: document.getElementById("editor"),
});

darkQuery.addEventListener("change", (e) => {
  view.dispatch({ effects: highlight.reconfigure(highlightFor(e.matches)) });
});

// Called by Swift after the page loads. A fresh state so undo history starts empty.
window.setDocument = (text) => {
  const started = performance.now();
  view.setState(EditorState.create({ doc: text, extensions: extensions() }));
  view.focus();
  const info = {
    event: "documentLoaded",
    lines: view.state.doc.lines,
    length: view.state.doc.length,
    ms: Math.round(performance.now() - started),
  };
  post(info);
  return info;
};

window.editorView = view; // for poking at it in Web Inspector
post({ event: "editorReady" });

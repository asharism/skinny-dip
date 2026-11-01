// CodeMirror 6 editor for Skinny Dip (Mac). Bundled into SkinnyDip/Resources/editor.bundle.js.
import { basicSetup } from "codemirror";
import { EditorView, keymap, rectangularSelection } from "@codemirror/view";
import { EditorState, Compartment, Prec } from "@codemirror/state";
import { addCursorAbove, addCursorBelow } from "@codemirror/commands";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";

function post(message) {
  try {
    window.webkit?.messageHandlers?.editor?.postMessage(message);
  } catch (_) {}
}

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

let suppressBridge = false;

function reportSelection(view) {
  const main = view.state.selection.main;
  post({
    event: "selectionChanged",
    from: main.from,
    to: main.to,
    rangeCount: view.state.selection.ranges.length,
  });
}

function extensions() {
  return [
    sublimeKeys,
    basicSetup,
    markdown({ base: markdownLanguage }),
    EditorView.lineWrapping,
    EditorState.allowMultipleSelections.of(true),
    rectangularSelection(),
    EditorView.contentAttributes.of({
      spellcheck: "true",
      autocorrect: "on",
      autocapitalize: "on",
      writingsuggestions: "true",
    }),
    baseTheme,
    highlight.of(highlightFor(darkQuery.matches)),
    EditorView.updateListener.of((update) => {
      if (suppressBridge) return;
      if (update.docChanged) {
        post({ event: "documentChanged", text: update.state.doc.toString() });
      }
      if (update.selectionSet || update.docChanged) {
        reportSelection(update.view);
      }
    }),
  ];
}

const view = new EditorView({
  state: EditorState.create({ doc: "", extensions: extensions() }),
  parent: document.getElementById("editor"),
});

darkQuery.addEventListener("change", (e) => {
  view.dispatch({ effects: highlight.reconfigure(highlightFor(e.matches)) });
});

window.setDocument = (text) => {
  suppressBridge = true;
  try {
    view.setState(EditorState.create({ doc: text, extensions: extensions() }));
    view.focus();
    reportSelection(view);
  } finally {
    suppressBridge = false;
  }
  return { event: "documentLoaded", length: view.state.doc.length };
};

window.selectAllDocument = () => {
  const len = view.state.doc.length;
  view.dispatch({ selection: { anchor: 0, head: len } });
  view.focus();
  reportSelection(view);
  return true;
};

window.editorView = view;
post({ event: "editorReady" });

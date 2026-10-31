// CodeMirror 6 editor for Skinny Dip (Mac). Bundled into SkinnyDip/Resources/editor.bundle.js.
import {
  lineNumbers,
  highlightActiveLineGutter,
  highlightSpecialChars,
  drawSelection,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
  highlightActiveLine,
  keymap,
  EditorView,
} from "@codemirror/view";
import { EditorState, Compartment, Prec } from "@codemirror/state";
import {
  foldGutter,
  indentOnInput,
  syntaxHighlighting,
  defaultHighlightStyle,
  bracketMatching,
  foldKeymap,
  HighlightStyle,
} from "@codemirror/language";
import {
  history,
  defaultKeymap,
  historyKeymap,
  addCursorAbove,
  addCursorBelow,
  undo,
  redo,
  undoDepth,
  redoDepth,
} from "@codemirror/commands";
import { highlightSelectionMatches, searchKeymap } from "@codemirror/search";
import {
  closeBrackets,
  autocompletion,
  closeBracketsKeymap,
  completionKeymap,
} from "@codemirror/autocomplete";
import { lintKeymap } from "@codemirror/lint";
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { tags as t } from "@lezer/highlight";

// Keep in sync with MarkdownCore `EditorUndoGrouping.newGroupDelayMilliseconds`.
const UNDO_GROUP_MS = 750;

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

function codeMirrorSetup() {
  return [
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    history({ newGroupDelay: UNDO_GROUP_MS }),
    foldGutter(),
    drawSelection(),
    dropCursor(),
    EditorState.allowMultipleSelections.of(true),
    indentOnInput(),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    bracketMatching(),
    closeBrackets(),
    autocompletion(),
    rectangularSelection(),
    crosshairCursor(),
    highlightActiveLine(),
    highlightSelectionMatches(),
    keymap.of([
      ...closeBracketsKeymap,
      ...defaultKeymap,
      ...searchKeymap,
      ...historyKeymap,
      ...foldKeymap,
      ...completionKeymap,
      ...lintKeymap,
    ]),
  ];
}

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

function reportHistory(view) {
  post({
    event: "historyChanged",
    canUndo: undoDepth(view.state) > 0,
    canRedo: redoDepth(view.state) > 0,
  });
}

function extensions() {
  return [
    sublimeKeys,
    codeMirrorSetup(),
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
        const immediate = update.transactions.some(
          (tr) => tr.isUserEvent("undo") || tr.isUserEvent("redo"),
        );
        post({
          event: "documentChanged",
          text: update.state.doc.toString(),
          immediate,
        });
      }
      if (update.selectionSet || update.docChanged) {
        reportSelection(update.view);
      }
      if (update.docChanged || update.transactions.some((tr) => tr.isUserEvent("undo") || tr.isUserEvent("redo"))) {
        reportHistory(update.view);
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
    reportHistory(view);
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

window.editorUndo = () => {
  undo(view);
  return true;
};

window.editorRedo = () => {
  redo(view);
  return true;
};

window.editorCut = () => {
  const changes = view.state.selection.ranges
    .map((range) => ({ from: range.from, to: range.to, insert: "" }))
    .filter((change) => change.from !== change.to);
  if (changes.length === 0) return false;
  view.dispatch({ changes, userEvent: "cut" });
  view.focus();
  return true;
};

window.insertText = (text) => {
  const { from, to } = view.state.selection.main;
  view.dispatch({
    changes: { from, to, insert: text },
    userEvent: "input.paste",
  });
  view.focus();
  return true;
};

window.editorView = view;
post({ event: "editorReady" });

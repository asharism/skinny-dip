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
  indentUnit,
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
  indentWithTab,
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
import { languages } from "@codemirror/language-data";
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

const lightHighlight = HighlightStyle.define([
  { tag: t.heading, fontWeight: "bold", color: "#1f2328" },
  { tag: [t.strong], fontWeight: "bold", color: "#1f2328" },
  { tag: [t.emphasis], fontStyle: "italic", color: "#1f2328" },
  { tag: t.strikethrough, textDecoration: "line-through", color: "#656d76" },
  { tag: [t.link, t.url], color: "#0969da", textDecoration: "underline" },
  { tag: [t.monospace], color: "#cf222e", backgroundColor: "#f6f8fa" },
  { tag: [t.keyword, t.processingInstruction], color: "#8250df" },
  { tag: [t.string], color: "#0a3069" },
  { tag: [t.number, t.atom, t.bool], color: "#0550ae" },
  { tag: [t.comment, t.meta, t.contentSeparator, t.quote], color: "#656d76" },
  { tag: [t.list], color: "#1f2328" },
]);

const darkHighlight = HighlightStyle.define([
  { tag: t.heading, fontWeight: "bold", color: "#e6edf3" },
  { tag: [t.strong], fontWeight: "bold", color: "#e6edf3" },
  { tag: [t.emphasis], fontStyle: "italic", color: "#e6edf3" },
  { tag: t.strikethrough, textDecoration: "line-through", color: "#8b949e" },
  { tag: [t.link, t.url], color: "#4493f8", textDecoration: "underline" },
  { tag: [t.monospace], color: "#ff7b72", backgroundColor: "#161b22" },
  { tag: [t.keyword, t.processingInstruction], color: "#d2a8ff" },
  { tag: [t.string], color: "#a5d6ff" },
  { tag: [t.number, t.atom, t.bool], color: "#79c0ff" },
  { tag: [t.comment, t.meta, t.contentSeparator, t.quote], color: "#8b949e" },
  { tag: [t.list], color: "#e6edf3" },
]);

const colorSchemeQuery = window.matchMedia("(prefers-color-scheme: dark)");
const highlight = new Compartment();
const highlightFor = (dark) =>
  syntaxHighlighting(dark ? darkHighlight : lightHighlight);

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
    indentUnit.of("  "),
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
      indentWithTab,
    ]),
  ];
}

let suppressBridge = false;

function reportSelection(view) {
  const main = view.state.selection.main;
  const hasSelection = view.state.selection.ranges.some((r) => r.from !== r.to);
  post({
    event: "selectionChanged",
    from: main.from,
    to: main.to,
    rangeCount: view.state.selection.ranges.length,
    hasSelection,
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
    markdown({
      base: markdownLanguage,
      codeLanguages: languages,
    }),
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
    highlight.of(highlightFor(colorSchemeQuery.matches)),
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

colorSchemeQuery.addEventListener("change", (e) => {
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

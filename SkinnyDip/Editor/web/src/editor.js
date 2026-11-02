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
  ViewPlugin,
  placeholder,
} from "@codemirror/view";
import { EditorState, Prec, EditorSelection } from "@codemirror/state";
import {
  foldGutter,
  indentOnInput,
  syntaxHighlighting,
  bracketMatching,
  foldKeymap,
  HighlightStyle,
  indentUnit,
} from "@codemirror/language";
import {
  history,
  historyField,
  defaultKeymap,
  historyKeymap,
  addCursorAbove,
  addCursorBelow,
  emacsStyleKeymap,
  undo,
  redo,
  undoDepth,
  redoDepth,
  indentWithTab,
  isolateHistory,
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
    { mac: "Cmd-Alt-ArrowUp", run: addCursorAbove, preventDefault: true },
    { mac: "Cmd-Alt-ArrowDown", run: addCursorBelow, preventDefault: true },
  ]),
);

const emacsKeys = Prec.highest(
  keymap.of(
    emacsStyleKeymap.map((binding) => ({
      mac: binding.key,
      run: binding.run,
      shift: binding.shift,
      preventDefault: true,
    })),
  ),
);

/** MarkEdit-style DOM attributes; CM defaults spellcheck off and resets attrs on updates. */
const nativeTextChecker = ViewPlugin.fromClass(
  class {
    update(update) {
      const dom = update.view.contentDOM;
      if (dom.getAttribute("spellcheck") !== "true") {
        dom.setAttribute("spellcheck", "true");
      }
      if (dom.getAttribute("autocorrect") !== "on") {
        dom.setAttribute("autocorrect", "on");
      }
      if (dom.getAttribute("writingsuggestions") !== "true") {
        dom.setAttribute("writingsuggestions", "true");
      }
      dom.removeAttribute("autocomplete");
      dom.removeAttribute("autocapitalize");
    }
  },
);

const skinnyHighlight = HighlightStyle.define([
  { tag: t.heading, fontWeight: "bold", color: "var(--heading)" },
  // Only the punctuation is a marker. `t.list` tags the whole list item, which
  // greyed out every bullet's text.
  { tag: [t.processingInstruction, t.contentSeparator], color: "var(--marker)" },
  { tag: t.emphasis, fontStyle: "italic", color: "var(--emphasis)" },
  { tag: t.strong, fontWeight: "bold", color: "var(--fg)" },
  { tag: [t.link, t.url], color: "var(--link)" },
  { tag: t.monospace, color: "var(--code)" },
  { tag: t.quote, fontStyle: "italic", color: "var(--quote)" },
  { tag: t.strikethrough, textDecoration: "line-through", color: "var(--muted)" },
]);

const baseTheme = EditorView.theme({
  "&": {
    height: "100%",
    backgroundColor: "transparent",
    color: "var(--fg)",
  },
  ".cm-scroller": {
    fontFamily: "ui-monospace, 'SF Mono', Menlo, monospace",
    fontSize: "var(--editor-font-size, 13px)",
    lineHeight: "1.65",
  },
  ".cm-content": {
    padding: "calc(8px * var(--zoom, 1)) var(--editor-inline-pad, 22px) calc(16px * var(--zoom, 1))",
    caretColor: "var(--cursor)",
  },
  ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--cursor)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
    backgroundColor: "var(--selection)",
  },
  ".cm-activeLine": {
    backgroundColor: "color-mix(in srgb, var(--selection) 50%, transparent)",
  },
  ".cm-gutters": {
    backgroundColor: "transparent",
    color: "var(--marker)",
    border: "none",
  },
  ".cm-activeLineGutter": { backgroundColor: "transparent" },
  ".cm-placeholder": { color: "var(--muted)" },
});

function codeMirrorSetup() {
  return [
    lineNumbers(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    // 10_000 steps so a long draft can undo back to empty. Scratch documents persist this history.
    history({ minDepth: 10000, newGroupDelay: UNDO_GROUP_MS }),
    foldGutter(),
    drawSelection(),
    dropCursor(),
    EditorState.allowMultipleSelections.of(true),
    indentOnInput(),
    indentUnit.of("  "),
    syntaxHighlighting(skinnyHighlight),
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
    head: main.head,
    rangeCount: view.state.selection.ranges.length,
    hasSelection,
  });
}

let lastViewportKey = "";
let viewportFrame = 0;

function reportViewport() {
  // Line blocks are measured from the document top, below the content padding.
  // A screen-coordinate probe lands in that padding and always reports line 1.
  const scroller = view.scrollDOM;
  if (!view.state.doc.length) {
    publishViewport(1, 0);
    return;
  }
  const paddingTop = view.documentPadding.top || 0;
  const probe = Math.max(0, scroller.scrollTop - paddingTop);
  const block = view.lineBlockAtHeight(probe);
  const lineNumber = view.state.doc.lineAt(block.from).number;
  const fraction = Math.min(1, Math.max(0, (probe - block.top) / Math.max(1, block.height)));
  publishViewport(lineNumber, fraction);
}

function publishViewport(lineNumber, fraction) {
  const key = `${lineNumber}:${fraction.toFixed(3)}`;
  if (key === lastViewportKey) return;
  lastViewportKey = key;
  post({ event: "viewport", topLine: lineNumber, fraction });
}

function scheduleViewport() {
  if (viewportFrame) return;
  viewportFrame = requestAnimationFrame(() => {
    viewportFrame = 0;
    reportViewport();
  });
}

function reportHistory(view) {
  post({
    event: "historyChanged",
    canUndo: undoDepth(view.state) > 0,
    canRedo: redoDepth(view.state) > 0,
  });
}

function currentExtensions() {
  return [
    placeholder("Start typing Markdown. ⌘V turns rich text into Markdown."),
    sublimeKeys,
    emacsKeys,
    nativeTextChecker,
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
    EditorView.updateListener.of((update) => {
      if (suppressBridge) return;
      if (update.docChanged) {
        const immediate = update.transactions.some(
          (tr) => tr.isUserEvent("undo") || tr.isUserEvent("redo") || tr.isUserEvent("input.paste"),
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
      if (update.geometryChanged || update.viewportChanged) scheduleViewport();
    }),
  ];
}

const view = new EditorView({
  state: EditorState.create({ doc: "", extensions: currentExtensions() }),
  parent: document.getElementById("editor"),
});

view.scrollDOM.addEventListener("scroll", scheduleViewport, { passive: true });

window.setTheme = (vars) => {
  if (!vars) return true;
  const root = document.documentElement;
  for (const key of Object.keys(vars)) {
    root.style.setProperty(key, String(vars[key]));
  }
  view.requestMeasure();
  return true;
};

window.setDocument = (text) => {
  suppressBridge = true;
  try {
    view.setState(EditorState.create({ doc: text, extensions: currentExtensions() }));
    view.focus();
    reportSelection(view);
    reportHistory(view);
    lastViewportKey = "";
    reportViewport();
  } finally {
    suppressBridge = false;
  }
  return { event: "documentLoaded", length: view.state.doc.length };
};

window.exportState = () => JSON.stringify(view.state.toJSON({ history: historyField }));

window.importState = (json) => {
  suppressBridge = true;
  try {
    const parsed = typeof json === "string" ? JSON.parse(json) : json;
    view.setState(
      EditorState.fromJSON(parsed, { extensions: currentExtensions() }, { history: historyField }),
    );
    view.focus();
    reportSelection(view);
    reportHistory(view);
    lastViewportKey = "";
    reportViewport();
    return true;
  } catch (_) {
    let doc = "";
    try {
      const parsed = typeof json === "string" ? JSON.parse(json) : json;
      if (parsed && typeof parsed.doc === "string") doc = parsed.doc;
    } catch (_) {}
    view.setState(EditorState.create({ doc, extensions: currentExtensions() }));
    post({ event: "historyRestoreFailed" });
    return false;
  } finally {
    suppressBridge = false;
  }
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

// Paste lands here (Swift reads the pasteboard; the sandboxed web process can't).
// Like CodeMirror's own paste: with one line per cursor, each cursor gets its
// line; otherwise every selection range gets the whole text. One undo step.
window.insertText = (text) => {
  const state = view.state;
  const insert = state.toText(text == null ? "" : String(text));
  const ranges = state.selection.ranges;
  let line = 1;
  const spec =
    ranges.length > 1 && insert.lines === ranges.length
      ? state.changeByRange((range) => {
          const piece = insert.line(line++).text;
          return {
            changes: { from: range.from, to: range.to, insert: piece },
            range: EditorSelection.cursor(range.from + piece.length),
          };
        })
      : state.replaceSelection(insert);
  view.dispatch(spec, {
    userEvent: "input.paste",
    scrollIntoView: true,
    annotations: isolateHistory.of("full"),
  });
  view.focus();
  // Returned to Swift. The documentChanged message carries the same text, but a
  // large paste can be dropped on that channel and the preview would stay stale.
  return view.state.doc.toString();
};

window.focusEditor = () => {
  view.focus();
  return true;
};

window.ensureWritingToolsSelection = () => {
  const selection = view.state.selection.main;
  const doc = view.state.doc;
  const { from } = doc.lineAt(selection.from);
  const { to } = doc.lineAt(selection.to);
  if (from === to) {
    view.dispatch({ selection: EditorSelection.range(0, doc.length) });
  } else {
    view.dispatch({ selection: EditorSelection.range(from, to) });
  }
  view.focus();
  return true;
};

window.editorView = view;
post({ event: "editorReady" });

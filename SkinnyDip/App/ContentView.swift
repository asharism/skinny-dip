import SwiftUI
#if os(macOS)
import AppKit
import MarkdownCore
#endif

struct ContentView: View {
    @Binding var document: MarkdownDocument
    var fileURL: URL? = nil
    #if os(macOS)
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.metrics) private var metrics
    @EnvironmentObject private var themes: ThemeStore
    @State private var selection: Range<String.Index>?
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var hasEditorSelection = false
    @State private var canPasteFromPasteboard = NSPasteboard.general.canPasteFromPasteboard
    @StateObject private var previewState = DocumentPreviewState()
    @StateObject private var editor = EditorController()
    @StateObject private var tabs = WindowTabModel()
    @State private var window: NSWindow?
    @State private var zoomed: CardKind?
    @State private var wordCount = 0
    @State private var displayTitle = DocumentTitle.untitled
    @State private var duplicateBaseline: String?
    @State private var localID = UUID()
    @State private var wordTask: Task<Void, Never>?
    @State private var titleTask: Task<Void, Never>?
    @State private var scratchTask: Task<Void, Never>?
    @AppStorage("showPreview") private var showPreview = true
    @AppStorage("previewLeadingFraction") private var previewLeadingFraction: Double = 0.5
    @AppStorage("paneOrientation") private var paneOrientation = "sideBySide"
    @AppStorage("scrollSync") private var scrollSync = true
    @AppStorage("themeMode") private var themeMode = ThemeSelection.matchSystem
    @AppStorage("themeFixed") private var themeFixed = ThemeSelection.defaultLight
    @AppStorage("themeLight") private var themeLight = ThemeSelection.defaultLight
    @AppStorage("themeDark") private var themeDark = ThemeSelection.defaultDark
    @AppStorage(RenderSettings.demotesHeadings) private var demotesHeadings = RenderOptions.default.demotesHeadings
    @AppStorage(RenderSettings.bordersTables) private var bordersTables = RenderOptions.default.bordersTables
    @AppStorage(RenderSettings.newlinesAsBreaks) private var newlinesAsBreaks = RenderOptions.default.newlinesAsBreaks
    #else
    @State private var textSelection: TextSelection?
    #endif

    var body: some View {
        #if os(macOS)
        shell
        #else
        TextEditor(text: $document.source, selection: $textSelection)
            .font(.body.monospaced())
            .focusedSceneValue(\.copySource, CopySource(
                markdown: document.source,
                selection: textSelection?.range(in: document.source)
            ))
        #endif
    }

    #if os(macOS)
    private var theme: ResolvedTheme {
        themes.resolved(
            mode: themeMode,
            fixed: themeFixed,
            light: themeLight,
            dark: themeDark,
            systemIsDark: colorScheme == .dark
        )
    }

    private var documentID: UUID { document.scratchID ?? localID }

    private var stacked: Bool { paneOrientation == "stacked" }

    private var themeVars: [String: String] {
        var vars = theme.cssVariables()
        vars["--editor-font-size"] = "\(metrics.editorFont)px"
        vars["--editor-inline-pad"] = "\(metrics.editorPad)px"
        vars["--zoom"] = String(metrics.zoom)
        return vars
    }

    private var shell: some View {
        let points = GradientAngle.points(degrees: 140)
        return ZStack {
            LinearGradient(
                colors: theme.windowGradient.map { Color($0) },
                startPoint: points.0,
                endPoint: points.1
            )
            .ignoresSafeArea()
            VStack(spacing: 0) {
                titleBar
                SplitPane(
                    leadingFraction: $previewLeadingFraction,
                    axis: stacked ? .vertical : .horizontal,
                    spacing: metrics.cardGap,
                    leadingVisible: zoomed != .preview,
                    trailingVisible: showPreview && zoomed != .editor
                ) {
                    editorCard
                } trailing: {
                    previewCard
                }
                .padding(.horizontal, metrics.cardPadding)
                .padding(.bottom, metrics.cardPadding)
                .padding(.top, metrics.cardPaddingTop)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(WindowChrome(
            title: displayTitle,
            background: NSColor(theme.windowGradient.first ?? theme.foreground),
            appearance: windowAppearance,
            model: tabs,
            onWindow: { next in
                if window !== next { window = next }
            }
        ))
        .onAppear {
            duplicateBaseline = document.pinnedTitle == nil ? nil : document.source
            applyTitle(immediate: true)
            scheduleWords(immediate: true)
            refreshPreview()
            editor.pendingHistory = ScratchRestore.history(forText: document.source, storedHistoryJSON: document.undoHistory)
            registerWindow()
        }
        .onChange(of: document.source) { _, newValue in
            if document.pinnedTitle != nil, newValue != duplicateBaseline {
                document.pinnedTitle = nil
            }
            refreshPreview()
            refreshPasteboardMenuState()
            applyTitle(immediate: false)
            scheduleWords(immediate: false)
            noteScratchEdit()
        }
        .onChange(of: demotesHeadings) { refreshPreview() }
        .onChange(of: bordersTables) { refreshPreview() }
        .onChange(of: newlinesAsBreaks) { refreshPreview() }
        .onChange(of: fileURL) { _, url in
            guard let url, let id = document.scratchID, isUserFile(url) else { return }
            ScratchSession.shared.discardScratch(id: id)
            document.scratchID = nil
            document.pinnedTitle = nil
            window?.isRestorable = true
            applyTitle(immediate: true)
        }
        .onChange(of: window) { registerWindow() }
        .onReceive(NotificationCenter.default.publisher(for: .togglePreview)) { _ in
            showPreview.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .duplicateDocument)) { _ in
            guard window?.isKeyWindow == true else { return }
            guard let window else { return }
            ScratchSession.shared.duplicate(window: window)
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTab)) { note in
            guard window?.isKeyWindow == true, let number = note.object as? Int else { return }
            tabs.selectIndex(number)
        }
    }

    private var windowAppearance: NSAppearance? {
        guard themeMode == ThemeSelection.fixed else { return nil }
        return NSAppearance(named: theme.appearance == .dark ? .darkAqua : .aqua)
    }

    private var titleBar: some View {
        HStack(spacing: metrics.chipPaddingH) {
            Color.clear.frame(width: metrics.trafficLightInset, height: metrics.titleButton)
            // The strip is only as wide as its Tabs, with + right after the last
            // one. Filling the bar left an empty shaded band with no purpose.
            GeometryReader { geometry in
                HStack(spacing: metrics.chipPaddingV * 2) {
                    TabStrip(
                        model: tabs,
                        theme: theme,
                        available: max(0, geometry.size.width - metrics.titleButton - metrics.chipPaddingV * 2)
                    )
                    TitleBarButton(systemName: "plus", title: nil, foreground: Color(theme.muted), background: Color.clear) {
                        DocumentTabs.newDocument(in: window ?? DocumentTabs.frontDocumentWindow())
                    }
                    .help("New Tab (⌘T)")
                    Spacer(minLength: 0)
                }
                .frame(height: geometry.size.height)
            }
            if !showPreview {
                TitleBarButton(
                    systemName: "sidebar.right",
                    title: "Show Preview",
                    foreground: Color(theme.foreground),
                    background: Color(theme.strip)
                ) { showPreview = true }
                .help("Show Preview (⇧⌘P)")
            }
        }
        .padding(.trailing, metrics.cardPadding)
        .frame(height: metrics.titleBar)
        // The bare title bar drags the window and zooms on double-click.
        .background(WindowDragArea())
    }

    private var editorCard: some View {
        Card(theme: theme) {
            HStack(spacing: metrics.chipPaddingV) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: metrics.tabIcon))
                    .foregroundStyle(Color(theme.accent))
                Text(displayTitle)
                    .font(.system(size: metrics.titleFont, weight: .semibold))
                    .lineLimit(1)
                Text("Markdown")
                    .font(.system(size: metrics.captionFont))
                    .foregroundStyle(Color(theme.muted))
                Spacer(minLength: 0)
                IconButton(systemName: "plus.square.on.square", help: "Duplicate (⇧⌘S)", label: "Duplicate", foreground: Color(theme.muted), hoverFill: Color(theme.strip)) {
                    guard let window else { return }
                    ScratchSession.shared.duplicate(window: window)
                }
                IconButton(
                    systemName: stacked ? "rectangle.split.2x1" : "rectangle.split.1x2",
                    help: stacked ? "Side by side" : "Stack Cards",
                    label: stacked ? "Side by side" : "Stack Cards",
                    foreground: Color(theme.muted),
                    hoverFill: Color(theme.strip)
                ) {
                    paneOrientation = stacked ? "sideBySide" : "stacked"
                }
                IconButton(
                    systemName: zoomed == .editor ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: zoomed == .editor ? "Restore" : "Maximize Editor",
                    label: zoomed == .editor ? "Restore" : "Maximize Editor",
                    foreground: Color(theme.muted),
                    hoverFill: Color(theme.strip)
                ) { toggleZoom(.editor) }
            }
            .padding(.leading, metrics.headerLeading)
            .padding(.trailing, metrics.headerTrailing)
        } content: {
            editorPane
        } footer: {
            editorFooter
        }
    }

    private var previewCard: some View {
        Card(theme: theme) {
            HStack(spacing: metrics.chipPaddingV) {
                Image(systemName: "eye")
                    .font(.system(size: metrics.tabIcon))
                    .foregroundStyle(Color(theme.accent))
                Text("Preview")
                    .font(.system(size: metrics.titleFont, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                CopySplitButton(
                    theme: theme,
                    documentID: documentID,
                    empty: document.source.isEmpty,
                    selection: selection?.isEmpty == false,
                    copyRichText: { copyRich() },
                    copyMarkdown: { copyMarkdown() },
                    copyHTML: { copyHTML() }
                )
                IconButton(
                    systemName: "link",
                    help: scrollSync ? "Scroll sync on" : "Scroll sync off",
                    label: scrollSync ? "Scroll sync on" : "Scroll sync off",
                    foreground: Color(scrollSync ? theme.accent : theme.muted),
                    fill: scrollSync ? Color(theme.strip) : .clear,
                    hoverFill: Color(theme.strip)
                ) { scrollSync.toggle() }
                .accessibilityAddTraits(.isToggle)
                IconButton(
                    systemName: zoomed == .preview ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: zoomed == .preview ? "Restore" : "Maximize Preview",
                    label: zoomed == .preview ? "Restore" : "Maximize Preview",
                    foreground: Color(theme.muted),
                    hoverFill: Color(theme.strip)
                ) { toggleZoom(.preview) }
                IconButton(systemName: "xmark", help: "Hide Preview (⇧⌘P)", label: "Hide Preview (⇧⌘P)", foreground: Color(theme.muted), hoverFill: Color(theme.strip)) {
                    showPreview = false
                }
            }
            .padding(.leading, metrics.headerLeading)
            .padding(.trailing, metrics.headerTrailing)
        } content: {
            PreviewView(
                html: previewState.html,
                markdown: document.source,
                documentID: documentID,
                themeVars: themeVars,
                zoom: metrics.zoom,
                scrollSync: scrollSync,
                syncActive: showPreview && zoomed == nil,
                viewport: editor.viewport
            )
        } footer: {
            previewFooter
        }
    }

    private var editorPane: some View {
        EditorView(
            text: $document.source,
            selection: $selection,
            canUndo: $canUndo,
            canRedo: $canRedo,
            hasEditorSelection: $hasEditorSelection,
            documentID: documentID,
            themeVars: themeVars,
            controller: editor
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusedSceneValue(\.copySource, CopySource(
            markdown: document.source,
            selection: selection,
            documentID: documentID
        ))
        .focusedSceneValue(\.editorHistoryMenuState, EditorHistoryMenuState(canUndo: canUndo, canRedo: canRedo))
        .focusedSceneValue(\.editorPasteboardMenuState, editorPasteboardMenuState)
        .onAppear { refreshPasteboardMenuState() }
        .onChange(of: hasEditorSelection) { refreshPasteboardMenuState() }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuWillOpen)) { _ in
            refreshPasteboardMenuState()
        }
    }

    private var editorFooter: some View {
        let position = TextPosition.lineColumn(in: document.source, utf16Offset: editor.cursorUTF16)
        let words = wordCount == 1 ? "1 word" : "\(wordCount.formatted()) words"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: metrics.chipPaddingH * 1.5) {
                Text(words).fixedSize()
                Text("Ln \(position.line), Col \(position.column)").fixedSize()
                Spacer(minLength: metrics.chipPaddingH)
                Text(saveState).fixedSize()
            }
            HStack(spacing: metrics.chipPaddingH * 1.5) {
                Text(words).fixedSize()
                Spacer(minLength: metrics.chipPaddingH)
                Text(saveState).fixedSize()
            }
            Text(words).fixedSize()
        }
        .font(.system(size: metrics.footerFont).monospacedDigit())
        .foregroundStyle(Color(theme.muted))
        .padding(.horizontal, metrics.headerLeading)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) { Rectangle().fill(Color(theme.border)).frame(height: metrics.borderWidth) }
    }

    private var previewFooter: some View {
        // Narrow Cards drop the words first and keep the chips whole: a chip
        // that truncates to "Table bord…" no longer says what it toggles.
        ViewThatFits(in: .horizontal) {
            previewFooterRow(caption: true, syncLabel: true)
            previewFooterRow(caption: false, syncLabel: true)
            previewFooterRow(caption: false, syncLabel: false)
            ScrollView(.horizontal, showsIndicators: false) {
                previewFooterRow(caption: false, syncLabel: false)
            }
        }
        .font(.system(size: metrics.footerFont))
        .foregroundStyle(Color(theme.muted))
        .padding(.horizontal, metrics.headerLeading)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) { Rectangle().fill(Color(theme.border)).frame(height: metrics.borderWidth) }
    }

    private func previewFooterRow(caption: Bool, syncLabel: Bool) -> some View {
        HStack(spacing: metrics.chipPaddingH) {
            if caption {
                Text("Copies with").fixedSize()
            }
            chip("Headings −1", help: "Copies every heading one level down, so a top heading doesn’t dominate an email.", isOn: demotesHeadings) {
                demotesHeadings.toggle()
            }
            chip("Table borders", help: "A single-line grid with padding. Outlook and Word show tables without it otherwise.", isOn: bordersTables) {
                bordersTables.toggle()
            }
            chip("Line breaks", help: "Keeps “Thanks,⏎Hitesh” on two lines. Off joins lines as CommonMark does.", isOn: newlinesAsBreaks) {
                newlinesAsBreaks.toggle()
            }
            Spacer(minLength: metrics.chipPaddingH)
            if syncLabel {
                Text(scrollSync ? "Scroll sync" : "Scroll sync off").fixedSize()
            }
        }
    }

    private func chip(_ title: String, help: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .fixedSize()
                .strikethrough(!isOn)
                .foregroundStyle(Color(isOn ? theme.foreground : theme.muted))
                .padding(.horizontal, metrics.chipPaddingH)
                .padding(.vertical, metrics.chipPaddingV)
                .background(isOn ? Color(theme.strip) : Color.clear, in: RoundedRectangle(cornerRadius: metrics.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    private var saveState: String {
        guard isUserFile(fileURL) else { return "Not saved" }
        let edited = (window?.windowController?.document as? NSDocument)?.isDocumentEdited ?? false
        return edited ? "Edited" : "Saved"
    }

    private var editorPasteboardMenuState: EditorPasteboardMenuState {
        EditorPasteboardMenuState(
            canCut: hasEditorSelection,
            canCopy: hasEditorSelection || !document.source.isEmpty,
            canPaste: canPasteFromPasteboard
        )
    }

    private func refreshPasteboardMenuState() {
        canPasteFromPasteboard = NSPasteboard.general.canPasteFromPasteboard
    }

    private func refreshPreview() {
        previewState.update(
            source: document.source,
            options: RenderOptions(
                demotesHeadings: demotesHeadings,
                bordersTables: bordersTables,
                newlinesAsBreaks: newlinesAsBreaks
            )
        )
    }

    private func toggleZoom(_ kind: CardKind) {
        if kind == .editor && !showPreview { return }
        zoomed = zoomed == kind ? nil : kind
    }

    private func applyTitle(immediate: Bool) {
        let next = computedTitle()
        if immediate {
            displayTitle = next
            window?.title = next
            tabs.refresh()
            return
        }
        titleTask?.cancel()
        titleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            displayTitle = next
            window?.title = next
            tabs.refresh()
        }
    }

    private func computedTitle() -> String {
        if let fileURL, isUserFile(fileURL) { return fileURL.lastPathComponent }
        if let pinned = document.pinnedTitle, !pinned.isEmpty { return pinned }
        return DocumentTitle.suggested(from: document.source)
    }

    private func isUserFile(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.path.contains("/Scratch/") { return false }
        if let document = window?.windowController?.document as? NSDocument, document.isDraft { return false }
        return true
    }

    private func scheduleWords(immediate: Bool) {
        let source = document.source
        if immediate {
            wordCount = WordCount.count(in: source)
            return
        }
        wordTask?.cancel()
        wordTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            wordCount = WordCount.count(in: source)
        }
    }

    private func noteScratchEdit() {
        ScratchSession.shared.noteText(
            scratchID: document.scratchID,
            window: window,
            text: document.source,
            suggested: computedTitle(),
            fileName: isUserFile(fileURL) ? fileURL?.lastPathComponent : nil
        )
        guard let id = document.scratchID else { return }
        clearEdited()
        scratchTask?.cancel()
        scratchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            let history = await editor.exportState?()
            ScratchSession.shared.flush(id: id, history: history)
            clearEdited()
            tabs.refresh()
        }
    }

    private func registerWindow() {
        guard let window else { return }
        ScratchSession.shared.attach(
            scratchID: document.scratchID,
            text: document.source,
            createdAt: document.createdAt,
            controller: editor,
            window: window,
            fileName: isUserFile(fileURL) ? fileURL?.lastPathComponent : nil,
            suggested: computedTitle()
        )
        tabs.attach(window)
        tabs.refresh()
    }

    private func clearEdited() {
        let window = window
        DispatchQueue.main.async {
            guard let document = window?.windowController?.document as? NSDocument, document.fileURL == nil || document.isDraft else { return }
            document.updateChangeCount(.changeCleared)
        }
    }

    private func copyRich() {
        CopyWriter.writeRichText(markdown: document.source, selection: selection, documentID: documentID)
    }

    private func copyMarkdown() {
        CopyWriter.writeMarkdown(markdown: document.source, selection: selection, documentID: documentID)
    }

    private func copyHTML() {
        CopyWriter.writeHTML(markdown: document.source, selection: selection, documentID: documentID)
    }
    #endif
}

#if os(macOS)
extension Notification.Name {
    static let editorMenuWillOpen = Notification.Name("skinnyDipEditorMenuWillOpen")
}
#endif

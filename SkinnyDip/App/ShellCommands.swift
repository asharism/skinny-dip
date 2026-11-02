#if os(macOS)
import AppKit
import SwiftUI
import MarkdownCore

struct TabCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") {
                DocumentTabs.newDocument(in: DocumentTabs.frontDocumentWindow())
            }
            .keyboardShortcut("n", modifiers: .command)
            Button("New Tab") {
                DocumentTabs.newDocument(in: DocumentTabs.frontDocumentWindow())
            }
            .keyboardShortcut("t", modifiers: .command)
        }
        CommandMenu("Tabs") {
            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Show Last Tab" : "Show Tab \(number)") {
                    NotificationCenter.default.post(name: .selectTab, object: number)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
        }
    }
}

struct DocumentCommands: Commands {
    @ObservedObject private var session = ScratchSession.shared
    private let relative = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some Commands {
        CommandGroup(after: .saveItem) {
            Button("Duplicate") {
                NotificationCenter.default.post(name: .duplicateDocument, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Reopen Closed Tab") {
                session.reopenMostRecent()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(session.recentlyClosed.isEmpty)
            Menu("Recently Closed") {
                if session.recentlyClosed.isEmpty {
                    Button("No Closed Tabs") {}
                        .disabled(true)
                } else {
                    ForEach(session.recentlyClosed, id: \.id) { entry in
                        Button("\(entry.title) · \(relative.localizedString(for: entry.closedAt, relativeTo: Date()))") {
                            session.reopen(id: entry.id)
                        }
                    }
                }
            }
        }
        CommandGroup(replacing: .printItem) {
            Button("Page Setup…") {
                if let window = NSApp.keyWindow {
                    NSPageLayout().beginSheet(using: NSPrintInfo.shared, on: window)
                } else {
                    NSApp.runPageLayout(nil)
                }
            }
            Button("Print…") {
                NotificationCenter.default.post(name: .printDocument, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)
        }
    }
}

struct ViewCommands: Commands {
    @AppStorage("uiZoom") private var uiZoom = 1.0
    @AppStorage("scrollSync") private var scrollSync = true
    @AppStorage("themeMode") private var themeMode = ThemeSelection.matchSystem
    @AppStorage("themeFixed") private var themeFixed = ThemeSelection.defaultLight
    @ObservedObject private var themes = ThemeStore()

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Menu("Theme") {
                Picker("Theme", selection: themeChoice) {
                    Text("Match System").tag(ThemeSelection.matchSystem)
                    Divider()
                    ForEach(themes.lightThemes, id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                    Divider()
                    ForEach(themes.darkThemes, id: \.id) { theme in
                        Text(theme.name).tag(theme.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Toggle("Scroll Sync", isOn: $scrollSync)
            Divider()
            Button("Zoom In") { uiZoom = ZoomLevel(uiZoom).next().value }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(ZoomLevel(uiZoom).isMaximum)
            Button("Zoom Out") { uiZoom = ZoomLevel(uiZoom).previous().value }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(ZoomLevel(uiZoom).isMinimum)
            Button("Actual Size") { uiZoom = ZoomLevel.reset().value }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(ZoomLevel(uiZoom).value == 1)
        }
    }

    private var themeChoice: Binding<String> {
        Binding(
            get: { themeMode == ThemeSelection.fixed ? themeFixed : ThemeSelection.matchSystem },
            set: { newValue in
                if newValue == ThemeSelection.matchSystem {
                    themeMode = ThemeSelection.matchSystem
                } else {
                    themeMode = ThemeSelection.fixed
                    themeFixed = newValue
                }
            }
        )
    }
}
#endif

#if os(macOS)
import SwiftUI
import MarkdownCore

/// The ⌘, window. General keeps the render toggles. Appearance picks themes and Zoom.
struct SettingsView: View {
    @Environment(\.metrics) private var metrics
    @EnvironmentObject private var themes: ThemeStore
    @AppStorage(RenderSettings.demotesHeadings) private var demotesHeadings = RenderOptions.default.demotesHeadings
    @AppStorage(RenderSettings.bordersTables) private var bordersTables = RenderOptions.default.bordersTables
    @AppStorage(RenderSettings.newlinesAsBreaks) private var newlinesAsBreaks = RenderOptions.default.newlinesAsBreaks
    @AppStorage("themeMode") private var themeMode = ThemeSelection.matchSystem
    @AppStorage("themeFixed") private var themeFixed = ThemeSelection.defaultLight
    @AppStorage("themeLight") private var themeLight = ThemeSelection.defaultLight
    @AppStorage("themeDark") private var themeDark = ThemeSelection.defaultDark
    @AppStorage("uiZoom") private var uiZoom = 1.0

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            appearance
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: metrics.settingsWidth)
        .padding(metrics.settingsPadding)
    }

    private var general: some View {
        Form {
            Toggle("Heading Demotion", isOn: $demotesHeadings)
            Text("Copies every heading one level down, so a top heading doesn’t dominate an email.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Table borders", isOn: $bordersTables)
            Text("A single-line grid with padding. Outlook and Word show tables without it otherwise.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Newlines as line breaks", isOn: $newlinesAsBreaks)
            Text("Keeps “Thanks,⏎Hitesh” on two lines. Off joins lines as CommonMark does.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var appearance: some View {
        Form {
            Picker("Theme", selection: $themeMode) {
                Text("Match System").tag(ThemeSelection.matchSystem)
                Text("Fixed").tag(ThemeSelection.fixed)
            }
            .pickerStyle(.segmented)
            if themeMode == ThemeSelection.fixed {
                Picker("Theme", selection: $themeFixed) {
                    ForEach(themes.files, id: \.id) { theme in
                        Label { Text(theme.name) } icon: { ThemeSwatch(theme: theme) }
                            .tag(theme.id)
                    }
                }
            } else {
                Picker("Light theme", selection: $themeLight) {
                    ForEach(themes.lightThemes, id: \.id) { theme in
                        Label { Text(theme.name) } icon: { ThemeSwatch(theme: theme) }
                            .tag(theme.id)
                    }
                }
                Picker("Dark theme", selection: $themeDark) {
                    ForEach(themes.darkThemes, id: \.id) { theme in
                        Label { Text(theme.name) } icon: { ThemeSwatch(theme: theme) }
                            .tag(theme.id)
                    }
                }
            }
            LabeledContent("Zoom") {
                HStack {
                    Picker("Zoom", selection: zoomTenths) {
                        ForEach(5...20, id: \.self) { tenths in
                            Text("\(tenths * 10)%").tag(tenths)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Reset") { uiZoom = ZoomLevel.reset().value }
                        .disabled(ZoomLevel(uiZoom).value == 1)
                }
            }
            Text("⌘+ and ⌘− zoom every window; ⌘0 returns to 100%.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

extension SettingsView {
    /// Zoom as whole tenths so the picker tags match exactly.
    fileprivate var zoomTenths: Binding<Int> {
        Binding(
            get: { Int((ZoomLevel(uiZoom).value * 10).rounded()) },
            set: { uiZoom = ZoomLevel(Double($0) / 10).value }
        )
    }
}

private struct ThemeSwatch: View {
    @Environment(\.metrics) private var metrics
    var theme: ThemeFile

    var body: some View {
        let resolved = theme.resolve()
        let points = GradientAngle.points(degrees: 140)
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: resolved.windowGradient.map { Color($0) },
                startPoint: points.0,
                endPoint: points.1
            )
            Circle()
                .fill(Color(resolved.accent))
                .padding(metrics.chipPaddingV)
        }
        .frame(width: metrics.swatchWidth, height: metrics.swatchHeight)
        .clipShape(RoundedRectangle(cornerRadius: metrics.chipRadius, style: .continuous))
    }
}
#endif

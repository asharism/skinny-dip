#if os(macOS)
import SwiftUI
import MarkdownCore

/// The ⌘, window. Each toggle is one `RenderOptions` field; the copy commands
/// read the same keys through `RenderSettings`.
struct SettingsView: View {
    @AppStorage(RenderSettings.demotesHeadings) private var demotesHeadings = RenderOptions.default.demotesHeadings
    @AppStorage(RenderSettings.bordersTables) private var bordersTables = RenderOptions.default.bordersTables
    @AppStorage(RenderSettings.newlinesAsBreaks) private var newlinesAsBreaks = RenderOptions.default.newlinesAsBreaks

    var body: some View {
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
        .padding(20)
        .frame(width: 420)
    }
}
#endif

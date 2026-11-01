import SwiftUI

@main
struct SkinnyDipApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        #if os(macOS)
        .commands { CopyCommands() }
        #endif

        #if os(macOS)
        Settings { SettingsView() }
        #endif
    }
}

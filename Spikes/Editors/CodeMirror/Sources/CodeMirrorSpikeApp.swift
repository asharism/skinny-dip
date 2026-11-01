import SwiftUI

@main
struct CodeMirrorSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeWindow(engine: "CodeMirror 6 (WKWebView)") { Editor() }
        }
    }
}

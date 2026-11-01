import SwiftUI

@main
struct STTextViewSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeWindow(engine: "STTextView 2.4.1") { Editor() }
        }
    }
}

import SwiftUI

@main
struct NSTextViewSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeWindow(engine: "NSTextView (TextKit 2)") { Editor() }
        }
    }
}

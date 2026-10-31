import Combine
import SwiftUI

/// Common chrome for every editor spike: the editor fills the window, and a
/// status bar shows which engine this is and the app's memory footprint.
struct SpikeWindow<Editor: View>: View {
    let engine: String
    @ViewBuilder let editor: () -> Editor

    @State private var memory = MemoryFootprint.current()
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            editor()
            Divider()
            HStack {
                Text(engine).bold()
                Text("\(SampleDocument.lineCount) lines")
                Spacer()
                Text("App memory: \(memory)")
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 700, minHeight: 500)
        .onReceive(timer) { _ in memory = MemoryFootprint.current() }
    }
}

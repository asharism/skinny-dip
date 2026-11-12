#if os(macOS)
import AppKit

/// Intercepts Writing Tools menu actions so the editor can prepare its selection first (MarkEdit `Application.swift`).
final class SkinnyDipApplication: NSApplication {
    override func sendAction(_ action: Selector, to target: Any?, from sender: Any?) -> Bool {
        if action == Self.showWritingToolsAction {
            Task { @MainActor in
                await EditorResponders.active()?.prepareWritingToolsSelection()
                try? await Task.sleep(nanoseconds: 100_000_000)
                super.sendAction(action, to: target, from: sender)
            }
            return true
        }
        return super.sendAction(action, to: target, from: sender)
    }

    private static let showWritingToolsAction = #selector(NSResponder.showWritingTools(_:))
}
#endif

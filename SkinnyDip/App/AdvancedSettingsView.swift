#if os(macOS)
import SwiftUI

/// Settings › Advanced: the Editor Backend (ADR-0010). The picker shows the
/// stored choice; a change is only stored once the user confirms the relaunch.
struct AdvancedSettingsView: View {
    @State private var chosen = EditorBackendKind.stored(in: .standard)
    @State private var pending: EditorBackendKind?
    @State private var relaunchFailed = false

    var body: some View {
        Form {
            Picker("Editor", selection: choice) {
                ForEach(EditorBackendKind.allCases, id: \.self) { kind in
                    Text(kind.isAvailable ? kind.title : "\(kind.title) (coming soon)")
                        .tag(kind)
                        .disabled(!kind.isAvailable)
                }
            }
            Text(EditorBackendSwitch.warning)
                .font(.caption).foregroundStyle(.secondary)
            if relaunchFailed {
                Text(EditorBackendSwitch.fallback)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .alert(
            "Switch editors?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { kind in
            Button("Relaunch") {
                pending = nil
                chosen = kind
                EditorBackendSwitch.relaunch(to: kind) { relaunchFailed = true }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { _ in
            Text(EditorBackendSwitch.warning)
        }
    }

    /// The picker never moves on its own: picking asks first, and Cancel leaves it where it was.
    private var choice: Binding<EditorBackendKind> {
        Binding(
            get: { chosen },
            set: { next in
                guard next != chosen, next.isAvailable else { return }
                pending = next
            }
        )
    }
}
#endif

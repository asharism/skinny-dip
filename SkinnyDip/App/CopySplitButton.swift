#if os(macOS)
import AppKit
import SwiftUI
import MarkdownCore

enum CopyKind: String {
    case richText
    case markdown
    case html

    var confirmation: String {
        switch self {
        case .richText: "Copied rich text"
        case .markdown: "Copied Markdown"
        case .html: "Copied HTML"
        }
    }

    init?(raw: String) {
        self.init(rawValue: raw)
    }
}

enum CopyFeedback {
    static func post(_ kind: CopyKind, documentID: UUID?) {
        var info: [String: Any] = ["kind": kind.rawValue]
        if let documentID { info["documentID"] = documentID.uuidString }
        NotificationCenter.default.post(name: .skinnyDipDidCopy, object: nil, userInfo: info)
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: kind.confirmation,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}

extension Notification.Name {
    static let skinnyDipDidCopy = Notification.Name("skinnyDipDidCopy")
}

struct CopySplitButton: View {
    @Environment(\.metrics) private var metrics
    var theme: ResolvedTheme
    var documentID: UUID
    var empty: Bool
    var selection: Bool
    var copyRichText: () -> Void
    var copyMarkdown: () -> Void
    var copyHTML: () -> Void

    @State private var confirmation: String?
    @State private var clearTask: Task<Void, Never>?

    var body: some View {
        let confirming = confirmation != nil
        HStack(spacing: 0) {
            Button(action: copyRichText) {
                // A narrow Preview drops the ⌘C hint, then the long label,
                // rather than truncating to "Copy as… ⌘C".
                ViewThatFits(in: .horizontal) {
                    label(confirmation ?? (selection ? "Copy Selection" : "Copy as Rich Text"), shortcut: confirmation == nil)
                    label(confirmation ?? (selection ? "Copy Selection" : "Copy as Rich Text"), shortcut: false)
                    label(confirming ? "Copied" : "Copy", shortcut: false)
                }
                .font(.system(size: metrics.captionFont, weight: .semibold))
                .padding(.horizontal, metrics.chipPaddingH)
                .frame(height: metrics.copyHeight)
            }
            .buttonStyle(.plain)
            .disabled(empty)
            .help(selection ? "Copy the selection as rich text (⌘C)" : "Copy the whole document as rich text (⌘C)")
            .accessibilityLabel(confirmation ?? (selection ? "Copy Selection" : "Copy as Rich Text"))
            Rectangle()
                .fill(Color(theme.onAccent).opacity(theme.appearance == .light ? 0.35 : 0.25))
                .frame(width: metrics.borderWidth, height: metrics.copyHeight)
            Menu {
                Button("Copy as Rich Text") { copyRichText() }
                Button("Copy as Markdown") { copyMarkdown() }
                Button("Copy as HTML") { copyHTML() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: metrics.captionFont, weight: .semibold))
                    .frame(width: metrics.copyHeight, height: metrics.copyHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More copy formats")
            .accessibilityLabel("More copy formats")
            .disabled(empty)
        }
        .foregroundStyle(Color(theme.onAccent))
        .background(
            Color(confirming ? theme.code : theme.accent),
            in: RoundedRectangle(cornerRadius: metrics.copyRadius, style: .continuous)
        )
        .opacity(empty ? 0.45 : 1)
        .accessibilityElement(children: .contain)
        .animation(.easeOut(duration: 0.15), value: confirming)
        .onReceive(NotificationCenter.default.publisher(for: .skinnyDipDidCopy)) { note in
            guard let id = note.userInfo?["documentID"] as? String, id == documentID.uuidString else { return }
            let kind = CopyKind(raw: note.userInfo?["kind"] as? String ?? "") ?? .richText
            confirmation = kind.confirmation
            clearTask?.cancel()
            clearTask = Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                confirmation = nil
            }
        }
    }

    private func label(_ title: String, shortcut: Bool) -> some View {
        HStack(spacing: metrics.chipPaddingV) {
            Image(systemName: confirmation != nil ? "checkmark" : "doc.on.doc")
            Text(title)
                .lineLimit(1)
                .fixedSize()
            if shortcut {
                Text("⌘C")
                    .opacity(0.7)
                    .fixedSize()
            }
        }
    }
}
#endif

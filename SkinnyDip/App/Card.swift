#if os(macOS)
import SwiftUI
import MarkdownCore

enum CardKind: Equatable {
    case editor
    case preview
}

struct Card<Header: View, Content: View, Footer: View>: View {
    @Environment(\.metrics) private var metrics
    var theme: ResolvedTheme
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: metrics.cardRadius, style: .continuous)
        VStack(spacing: 0) {
            header()
                .frame(height: metrics.headerHeight)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer()
                .frame(height: metrics.footerHeight)
        }
        .background(shape.fill(Color(theme.card)))
        .clipShape(shape)
        .overlay(shape.stroke(Color(theme.border), lineWidth: metrics.borderWidth))
        .shadow(color: Color(theme.shadows.first?.color ?? RGBA(hex: "#000000").withAlpha(0.05)), radius: (theme.shadows.first?.blur ?? 2) * metrics.zoom, y: theme.shadows.first?.y ?? 1)
        .shadow(color: Color(theme.shadows.dropFirst().first?.color ?? RGBA(hex: "#000000").withAlpha(0)), radius: (theme.shadows.dropFirst().first?.blur ?? 0) * metrics.zoom, y: theme.shadows.dropFirst().first?.y ?? 0)
    }
}

struct IconButton: View {
    @Environment(\.metrics) private var metrics
    var systemName: String
    var help: String
    var label: String
    var foreground: Color
    var fill: Color = .clear
    var hoverFill: Color = .clear
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: metrics.captionFont, weight: .medium))
                .frame(width: metrics.iconButton, height: metrics.iconButton)
                .foregroundStyle(foreground)
                .background(hovering ? hoverFill : fill, in: RoundedRectangle(cornerRadius: metrics.iconRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .onHover { hovering = $0 }
    }
}

struct TitleBarButton: View {
    @Environment(\.metrics) private var metrics
    var systemName: String
    var title: String?
    var foreground: Color
    var background: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.chipPaddingV) {
                Image(systemName: systemName)
                if let title {
                    Text(title)
                        .font(.system(size: metrics.captionFont, weight: .medium))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, title == nil ? 0 : metrics.chipPaddingH)
            .frame(width: title == nil ? metrics.titleButton : nil, height: metrics.titleButton)
            .background(background, in: RoundedRectangle(cornerRadius: metrics.titleButtonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title ?? "New Tab")
    }
}
#endif

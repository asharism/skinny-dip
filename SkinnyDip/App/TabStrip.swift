#if os(macOS)
import SwiftUI
import MarkdownCore

struct TabStrip: View {
    @Environment(\.metrics) private var metrics
    @ObservedObject var model: WindowTabModel
    var theme: ResolvedTheme
    /// Width the strip may grow to; it hugs its Tabs below that.
    var available: CGFloat
    /// The Tab under the pointer while dragging, and how far it has moved.
    @State private var dragging: ObjectIdentifier?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        let count = max(model.items.count, 1)
        let room = max(0, available - metrics.stripInset * 2)
        let roomy = metrics.tabMaxWidth * CGFloat(count) <= room
        // Full width while they fit, then shrink evenly to the minimum, then scroll.
        let width = roomy ? metrics.tabMaxWidth : max(metrics.tabMinWidth, room / CGFloat(count))
        let stripWidth = min(available, width * CGFloat(count) + metrics.stripInset * 2)
        ScrollViewReader { scroller in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        let isDragging = dragging == item.id
                        TabCapsule(item: item, theme: theme, width: width, lifted: isDragging) {
                            model.select(item.id)
                        } close: {
                            model.close(item.id)
                        }
                        .offset(isDragging ? CGSize(width: dragOffset.width, height: dragOffset.height * 0.35) : .zero)
                        .zIndex(isDragging ? 1 : 0)
                        .simultaneousGesture(drag(item: item, index: index, width: width))
                        .contextMenu {
                            Button("New Tab") { model.newTab() }
                            Button("Duplicate") { model.duplicate(item.id) }
                            Divider()
                            Button("Move Tab to New Window") { model.moveToNewWindow(item.id) }
                                .disabled(model.items.count < 2)
                            Divider()
                            Button("Close Tab") { model.close(item.id) }
                            Button("Close Other Tabs") { model.closeOthers(keeping: item.id) }
                                .disabled(model.items.count < 2)
                            Button("Close Tabs to the Right") { model.closeToTheRight(of: item.id) }
                                .disabled(index >= model.items.count - 1)
                        }
                        .id(item.id)
                    }
                }
                .padding(metrics.stripInset)
            }
            .onChange(of: model.items.first(where: \.isSelected)?.id) { _, selected in
                guard let selected else { return }
                withAnimation(.easeOut(duration: 0.15)) { scroller.scrollTo(selected) }
            }
        }
        .frame(width: stripWidth, height: metrics.stripHeight)
        .background(Color(theme.strip), in: RoundedRectangle(cornerRadius: metrics.stripRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document tabs")
    }

    private func drag(item: WindowTabModel.Item, index: Int, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragging = item.id
                dragOffset = value.translation
            }
            .onEnded { value in
                defer {
                    dragging = nil
                    dragOffset = .zero
                }
                if abs(value.translation.height) > metrics.detachDistance,
                   abs(value.translation.height) > abs(value.translation.width),
                   model.items.count > 1 {
                    model.moveToNewWindow(item.id)
                    return
                }
                let shift = Int((value.translation.width / max(width, 1)).rounded())
                let destination = min(max(0, index + shift), model.items.count - 1)
                model.move(from: index, to: destination)
            }
    }
}

private struct TabCapsule: View {
    @Environment(\.metrics) private var metrics
    var item: WindowTabModel.Item
    var theme: ResolvedTheme
    var width: CGFloat
    var lifted = false
    var select: () -> Void
    var close: () -> Void
    @State private var hovering = false
    @State private var closeHovering = false

    var body: some View {
        HStack(spacing: metrics.chipPaddingV) {
            Button(action: select) {
                HStack(spacing: metrics.chipPaddingV) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: metrics.tabIcon))
                    Text(item.title)
                        .font(.system(size: metrics.tabFont, weight: item.isSelected ? .semibold : .medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title + (item.isEdited ? ", edited" : ""))
            .accessibilityAddTraits(item.isSelected ? .isSelected : [])
            // One trailing slot, so the title never jumps: the edited dot turns
            // into ✕ under the pointer, as in Safari and VS Code.
            ZStack {
                if hovering || (item.isSelected && !item.isEdited) {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: metrics.captionFont * 0.85, weight: .semibold))
                            .frame(width: metrics.tabIcon + metrics.chipPaddingV * 2, height: metrics.tabIcon + metrics.chipPaddingV * 2)
                            .background(closeHovering ? Color(theme.strip) : .clear, in: RoundedRectangle(cornerRadius: metrics.chipRadius * 0.8, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { closeHovering = $0 }
                    .help("Close Tab (⌘W)")
                    .accessibilityLabel("Close \(item.title)")
                } else if item.isEdited {
                    Circle()
                        .fill(Color(item.isSelected ? theme.foreground : theme.muted))
                        .frame(width: metrics.editedDot, height: metrics.editedDot)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: metrics.tabIcon + metrics.chipPaddingV * 2)
        }
        .padding(.horizontal, metrics.chipPaddingH)
        .frame(width: width, height: metrics.tabHeight)
        .foregroundStyle(Color(item.isSelected ? theme.foreground : theme.muted))
        .background {
            if item.isSelected || lifted {
                RoundedRectangle(cornerRadius: metrics.tabRadius, style: .continuous)
                    .fill(Color(theme.tab))
                    .overlay(
                        RoundedRectangle(cornerRadius: metrics.tabRadius, style: .continuous)
                            .stroke(Color(theme.border), lineWidth: metrics.borderWidth)
                    )
                    .shadow(color: Color(theme.shadows.first?.color ?? RGBA(hex: "#000000").withAlpha(0.05)), radius: (lifted ? 8 : 2) * metrics.zoom, y: (lifted ? 3 : 1) * metrics.zoom)
            } else if hovering {
                RoundedRectangle(cornerRadius: metrics.tabRadius, style: .continuous)
                    .fill(Color(theme.strip))
            }
        }
        .help(item.title)
        .onHover { hovering = $0 }
    }
}
#endif

#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers
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
        .overlay(alignment: .leading) {
            // The gap a Tab or file from elsewhere will land in.
            if let slot = model.dropSlot {
                Capsule()
                    .fill(Color(theme.accent))
                    .frame(width: 2 * metrics.zoom, height: metrics.tabHeight * 0.7)
                    .offset(x: metrics.stripInset + CGFloat(slot) * width - metrics.zoom)
                    .allowsHitTesting(false)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            model.noteStrip(frame: frame, tabWidth: width, inset: metrics.stripInset)
        }
        .onChange(of: width) { _, width in
            model.noteStrip(frame: nil, tabWidth: width, inset: metrics.stripInset)
        }
        .onDrop(of: [.fileURL], delegate: FileDrop(model: model))
        // AppKit moves the window on any drag in the title bar, Tabs included, so
        // a Tab could never be dragged. Over the strip the window holds still;
        // everywhere else (the bare title bar, Window ▸ Fill, Center) it moves.
        .onHover { inside in
            if dragging == nil { model.window?.isMovable = !inside }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document tabs")
    }

    private func drag(item: WindowTabModel.Item, index: Int, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragging = item.id
                dragOffset = value.translation
                let point = NSEvent.mouseLocation
                model.dragMoved(to: point, detachDistance: metrics.detachDistance)
                // Outside its own window the lifted Tab can't be drawn, so a ghost follows the pointer.
                if let frame = model.window?.frame, !frame.contains(point) {
                    TabGhost.show(title: item.title, theme: theme, metrics: metrics, at: point)
                } else {
                    TabGhost.hide()
                }
            }
            .onEnded { value in
                defer {
                    dragging = nil
                    dragOffset = .zero
                    model.dragEnded()
                    TabGhost.hide()
                    // The pointer may have left the strip mid-drag without a hover update.
                    for window in NSApp.windows where !window.isMovable && window.tabbingIdentifier == "SkinnyDipDocument" {
                        window.isMovable = true
                    }
                }
                let point = NSEvent.mouseLocation
                let (drop, target) = model.drop(at: point, detachDistance: metrics.detachDistance)
                switch drop {
                case .reorder:
                    let shift = Int((value.translation.width / max(width, 1)).rounded())
                    let destination = min(max(0, index + shift), model.items.count - 1)
                    model.move(from: index, to: destination)
                case .join(_, let slot):
                    if let target { model.join(item.id, to: target, at: slot) }
                case .newWindow:
                    model.moveToNewWindow(item.id, grabbedAt: point)
                case .none:
                    break
                }
            }
    }
}

/// Markdown or text files dragged in from Finder open as Tabs at the gap under the pointer.
private struct FileDrop: DropDelegate {
    let model: WindowTabModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let slot = model.slot(atStripX: info.location.x)
        if model.dropSlot != slot { model.dropSlot = slot }
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) { model.dropSlot = nil }

    func performDrop(info: DropInfo) -> Bool {
        let slot = model.slot(atStripX: info.location.x)
        model.dropSlot = nil
        let providers = info.itemProviders(for: [.fileURL])
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.url(from: provider), Self.isText(url) { urls.append(url) }
            }
            model.openFiles(urls, at: slot)
        }
        return true
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    static func isText(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .plainText) || type.conforms(to: UTType("net.daringfireball.markdown") ?? .plainText)
    }
}

/// A borderless copy of the dragged Tab that follows the pointer outside its window.
@MainActor
private enum TabGhost {
    private static var panel: NSPanel?

    static func show(title: String, theme: ResolvedTheme, metrics: Metrics, at point: NSPoint) {
        let size = NSSize(width: metrics.tabMaxWidth, height: metrics.tabHeight)
        let panel = panel ?? {
            let made = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            made.isOpaque = false
            made.backgroundColor = .clear
            made.hasShadow = true
            made.ignoresMouseEvents = true
            made.level = .floating
            made.alphaValue = 0.9
            Self.panel = made
            return made
        }()
        if panel.contentView?.toolTip != title {
            let label = HStack(spacing: metrics.chipPaddingV) {
                Image(systemName: "doc.plaintext").font(.system(size: metrics.tabIcon))
                Text(title).font(.system(size: metrics.tabFont, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.chipPaddingH)
            .frame(width: size.width, height: size.height)
            .foregroundStyle(Color(theme.foreground))
            .background(Color(theme.tab), in: RoundedRectangle(cornerRadius: metrics.tabRadius, style: .continuous))
            let host = NSHostingView(rootView: label)
            host.toolTip = title
            panel.contentView = host
            panel.setContentSize(size)
        }
        panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
        panel.orderFront(nil)
    }

    static func hide() {
        panel?.orderOut(nil)
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

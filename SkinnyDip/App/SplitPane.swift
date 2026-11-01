import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Shared editor/preview split (HStack + drag handle), not macOS-only `HSplitView`.
struct SplitPane<Leading: View, Trailing: View>: View {
    @Binding var leadingFraction: Double
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    private let minFraction = 0.2
    private let maxFraction = 0.8

    @State private var dragStartFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                leading()
                    .frame(
                        width: max(1, geometry.size.width * leadingFraction),
                        height: max(1, geometry.size.height)
                    )
                SplitHandle(isDragging: dragStartFraction != nil)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartFraction == nil {
                                    dragStartFraction = leadingFraction
                                }
                                guard let start = dragStartFraction else { return }
                                let next = start + value.translation.width / geometry.size.width
                                leadingFraction = min(max(next, minFraction), maxFraction)
                            }
                            .onEnded { _ in dragStartFraction = nil }
                    )
                trailing()
                    .frame(
                        width: max(1, geometry.size.width * (1 - leadingFraction) - 5),
                        height: max(1, geometry.size.height)
                    )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

private struct SplitHandle: View {
    var isDragging: Bool

    var body: some View {
        Rectangle()
            .fill(isDragging ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.12))
            .frame(width: 5)
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            #endif
    }
}

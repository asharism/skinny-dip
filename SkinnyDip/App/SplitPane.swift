import SwiftUI

/// Editor/Preview split. The gap between the panes is the drag handle.
struct SplitPane<Leading: View, Trailing: View>: View {
    enum Axis { case horizontal, vertical }

    @Binding var leadingFraction: Double
    var axis: Axis = .horizontal
    var spacing: CGFloat
    var leadingVisible = true
    var trailingVisible = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    private let minFraction = 0.2
    private let maxFraction = 0.8
    @State private var dragStartFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            let length = axis == .horizontal ? geometry.size.width : geometry.size.height
            let gap = leadingVisible && trailingVisible ? spacing : 0
            let lead = leadingVisible && trailingVisible
                ? max(1, length * leadingFraction)
                : (leadingVisible ? length : 0)
            let trail = max(0, length - lead - gap)
            let layout = axis == .horizontal
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                leading()
                    .frame(
                        width: axis == .horizontal ? (leadingVisible ? lead : 0) : geometry.size.width,
                        height: axis == .vertical ? (leadingVisible ? lead : 0) : geometry.size.height
                    )
                    .opacity(leadingVisible ? 1 : 0)
                    .accessibilityHidden(!leadingVisible)
                    .allowsHitTesting(leadingVisible)
                if leadingVisible && trailingVisible {
                    handle(length: length)
                }
                trailing()
                    .frame(
                        width: axis == .horizontal ? (trailingVisible ? trail : 0) : geometry.size.width,
                        height: axis == .vertical ? (trailingVisible ? trail : 0) : geometry.size.height
                    )
                    .opacity(trailingVisible ? 1 : 0)
                    .accessibilityHidden(!trailingVisible)
                    .allowsHitTesting(trailingVisible)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func handle(length: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(
                width: axis == .horizontal ? spacing : nil,
                height: axis == .vertical ? spacing : nil
            )
            .contentShape(Rectangle())
            // Double-click puts the split back to even, like Xcode and Finder.
            .onTapGesture(count: 2) { leadingFraction = 0.5 }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartFraction == nil { dragStartFraction = leadingFraction }
                        guard let start = dragStartFraction, length > 0 else { return }
                        let delta = axis == .horizontal ? value.translation.width : value.translation.height
                        leadingFraction = min(max(start + delta / length, minFraction), maxFraction)
                    }
                    .onEnded { _ in dragStartFraction = nil }
            )
            #if os(macOS)
            // pointerStyle stays balanced; push/pop on hover left the resize
            // cursor stuck whenever a drag ended outside the gap.
            .pointerStyle(axis == .horizontal ? .columnResize : .rowResize)
            #endif
            .accessibilityElement()
            .accessibilityLabel("Split")
            .accessibilityValue("\(Int((leadingFraction * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.05 : -0.05
                leadingFraction = min(max(leadingFraction + step, minFraction), maxFraction)
            }
    }
}

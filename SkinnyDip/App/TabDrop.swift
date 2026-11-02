import CoreGraphics

/// Where a dragged Tab lands when the pointer is let go. Pure geometry, in screen
/// coordinates, so it is tested without windows.
enum TabDrop: Equatable {
    /// Back into its own strip: reorder by the drag distance.
    case reorder
    /// Into another window's strip (`target` indexes `others`), before Tab `slot`.
    case join(target: Int, slot: Int)
    /// Out of every strip: the Tab becomes a window of its own.
    case newWindow
    /// Nothing changes: the window's only Tab let go outside every strip.
    case none

    /// One window's Tab strip.
    struct Strip: Equatable {
        var frame: CGRect
        var tabWidth: CGFloat
        var inset: CGFloat
        var count: Int

        /// The gap between Tabs nearest `x`, from 0 (before the first) to `count`.
        func slot(at x: CGFloat) -> Int {
            guard tabWidth > 0 else { return count }
            let raw = ((x - frame.minX - inset) / tabWidth).rounded()
            return min(max(0, Int(raw)), count)
        }
    }

    /// Pointer slack around another strip, so a near miss still lands.
    static let joinSlack: CGFloat = 10

    /// `others` are the other windows' strips, front to back; the first under the pointer wins.
    static func resolve(point: CGPoint, own: Strip, detachDistance: CGFloat, others: [Strip]) -> TabDrop {
        let home = own.frame.insetBy(dx: -detachDistance, dy: -detachDistance)
        if home.contains(point) { return .reorder }
        if let target = others.firstIndex(where: { $0.frame.insetBy(dx: -joinSlack, dy: -joinSlack).contains(point) }) {
            return .join(target: target, slot: others[target].slot(at: point.x))
        }
        return own.count > 1 ? .newWindow : .none
    }
}

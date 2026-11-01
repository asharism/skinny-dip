import Foundation

/// Whole-window zoom, 50%...200% in 10% steps. Stored as tenths so repeated
/// ⌘+ / ⌘− steps do not drift.
public struct ZoomLevel: Equatable, Sendable {
    public static let minimum = 0.5
    public static let maximum = 2.0
    public static let step = 0.1

    public let value: Double

    public init(_ raw: Double) {
        let clamped = min(Self.maximum, max(Self.minimum, raw))
        let tenths = Int((clamped * 10).rounded())
        value = Double(tenths) / 10
    }

    public static func reset() -> ZoomLevel { ZoomLevel(1) }

    public func next() -> ZoomLevel { ZoomLevel(value + Self.step) }

    public func previous() -> ZoomLevel { ZoomLevel(value - Self.step) }

    public var isMinimum: Bool { value <= Self.minimum }
    public var isMaximum: Bool { value >= Self.maximum }
}

import SwiftUI
import MarkdownCore
#if os(macOS)
import AppKit
#endif

extension Color {
    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

#if os(macOS)
extension NSColor {
    convenience init(_ rgba: RGBA) {
        self.init(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}
#endif

enum GradientAngle {
    /// CSS `linear-gradient` angle: 0° is up and degrees increase clockwise.
    static func points(degrees: Double) -> (UnitPoint, UnitPoint) {
        let radians = degrees * .pi / 180
        let dx = sin(radians)
        let dy = -cos(radians)
        return (
            UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2),
            UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
        )
    }
}

import SwiftUI

/// Sizes from the UI Shell spec at 100% Zoom, scaled by `uiZoom`.
struct Metrics: Equatable {
    var zoom: Double

    private func scaled(_ base: Double) -> CGFloat { CGFloat(base * zoom) }

    /// Never below 52: the unified toolbar keeps the traffic lights centred in
    /// a 52 pt title bar, and a shorter bar would slide the Cards under them.
    var titleBar: CGFloat { max(52, scaled(52)) }
    /// The strip hugs its Tabs: one Tab plus the inset above and below.
    var stripHeight: CGFloat { tabHeight + stripInset * 2 }
    var trafficLightInset: CGFloat { 84 }
    var tabHeight: CGFloat { scaled(32) }
    var tabMaxWidth: CGFloat { scaled(210) }
    var tabMinWidth: CGFloat { scaled(120) }
    var tabRadius: CGFloat { scaled(9) }
    var tabFont: CGFloat { scaled(12.5) }
    var tabIcon: CGFloat { scaled(14) }
    var editedDot: CGFloat { scaled(7) }
    var titleButton: CGFloat { scaled(30) }
    var titleButtonRadius: CGFloat { scaled(8) }
    var stripInset: CGFloat { scaled(3) }
    var stripRadius: CGFloat { scaled(12) }
    var cardRadius: CGFloat { scaled(12) }
    var cardPadding: CGFloat { scaled(12) }
    var cardPaddingTop: CGFloat { scaled(2) }
    var cardGap: CGFloat { scaled(10) }
    var headerHeight: CGFloat { scaled(40) }
    var headerLeading: CGFloat { scaled(14) }
    var headerTrailing: CGFloat { scaled(8) }
    var footerHeight: CGFloat { scaled(28) }
    var footerFont: CGFloat { scaled(11.5) }
    var titleFont: CGFloat { scaled(13) }
    var captionFont: CGFloat { scaled(12) }
    var iconButton: CGFloat { scaled(28) }
    var iconRadius: CGFloat { scaled(7) }
    var editorFont: CGFloat { scaled(13) }
    var editorPad: CGFloat { scaled(22) }
    var borderWidth: CGFloat { max(1, scaled(1)) }
    var copyHeight: CGFloat { scaled(28) }
    var copyRadius: CGFloat { scaled(8) }
    var detachDistance: CGFloat { scaled(30) }
    var settingsWidth: CGFloat { 460 }
    var settingsPadding: CGFloat { scaled(20) }
    var swatchWidth: CGFloat { scaled(28) }
    var swatchHeight: CGFloat { scaled(16) }
    var chipRadius: CGFloat { scaled(6) }
    var chipPaddingH: CGFloat { scaled(8) }
    var chipPaddingV: CGFloat { scaled(3) }
}

private struct MetricsKey: EnvironmentKey {
    static let defaultValue = Metrics(zoom: 1)
}

extension EnvironmentValues {
    var metrics: Metrics {
        get { self[MetricsKey.self] }
        set { self[MetricsKey.self] = newValue }
    }
}

#if os(macOS) && DEBUG
import AppKit
import WebKit

/// Debug builds only: lets an agent see the window without Screen Recording permission.
/// Launch with `SKINNYDIP_SNAPSHOT=/path/shot.png`, then create `/path/shot.png.trigger`;
/// the key window (SwiftUI layer plus each web view) is written to the PNG and the trigger removed.
/// Creating `/path/shot.png.layout` instead writes the windows and their Tabs, one window
/// per line in front-to-back order with the window frame and the Tab strip in screen
/// coordinates, to `/path/shot.png.layout.txt`.
@MainActor
enum DebugSnapshot {
    private static var timer: Timer?

    static func installIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["SKINNYDIP_SNAPSHOT"], !path.isEmpty else { return }
        let trigger = path + ".trigger"
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                guard FileManager.default.fileExists(atPath: trigger) else { return }
                try? FileManager.default.removeItem(atPath: trigger)
                await capture(to: URL(fileURLWithPath: path))
            }
            Task { @MainActor in
                let layout = path + ".layout"
                guard FileManager.default.fileExists(atPath: layout) else { return }
                try? FileManager.default.removeItem(atPath: layout)
                try? describeWindows().write(toFile: layout + ".txt", atomically: true, encoding: .utf8)
            }
        }
    }

    private static func capture(to url: URL) async {
        let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible }
        guard let root = window?.contentView?.superview ?? window?.contentView else { return }
        let bounds = root.bounds
        guard let rep = root.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        root.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)

        var webViews: [WKWebView] = []
        collect(root, into: &webViews)
        for webView in webViews where !webView.isHiddenOrHasHiddenAncestor && webView.bounds.width > 1 {
            let frame = webView.convert(webView.bounds, to: root)
            // takeSnapshot drops transparency; paint the Card colour from the
            // SwiftUI layer underneath so the snapshot matches the window.
            // Sample just above the web view: the Card header has the same fill.
            let probe = NSPoint(x: frame.midX, y: root.isFlipped ? frame.minY - 4 : bounds.height - frame.maxY - 4)
            let backing = rep.colorAt(x: Int(probe.x * CGFloat(rep.pixelsWide) / bounds.width),
                                      y: Int(probe.y * CGFloat(rep.pixelsHigh) / bounds.height))?.usingColorSpace(.sRGB)
            let css = backing.map { String(format: "rgb(%d,%d,%d)", Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255)) } ?? "transparent"
            _ = try? await webView.evaluateJavaScript("document.documentElement.style.background='\(css)'")
            let config = WKSnapshotConfiguration()
            let shot = try? await webView.takeSnapshot(configuration: config)
            _ = try? await webView.evaluateJavaScript("document.documentElement.style.background=''")
            guard let shot else { continue }
            image.lockFocus()
            let flipped = root.isFlipped
                ? NSRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
                : frame
            shot.draw(in: flipped, from: .zero, operation: .sourceOver, fraction: 1)
            image.unlockFocus()
        }
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }

    /// `[a.md, *b.md] key` for a window with two Tabs, `b.md` selected, that is key.
    static func describeWindows() -> String {
        var seen = Set<ObjectIdentifier>()
        var lines: [String] = []
        for window in NSApp.orderedWindows where window.tabbingIdentifier == "SkinnyDipDocument" && window.isVisible {
            let tabs = window.tabGroup?.windows ?? [window]
            let key = ObjectIdentifier(window.tabGroup ?? window)
            guard seen.insert(key).inserted else { continue }
            let selected = window.tabGroup?.selectedWindow ?? window
            let titles = tabs.map { ($0 === selected ? "*" : "") + ($0.title.isEmpty ? "Untitled" : $0.title) }
            let isKey = tabs.contains { $0.isKeyWindow }
            var line = "[" + titles.joined(separator: ", ") + "]" + (isKey ? " key" : "")
            let w = selected.frame
            line += String(format: " window=%.0f,%.0f,%.0f,%.0f", w.minX, w.minY, w.width, w.height)
            if let strip = WindowTabModel.screenStrip(of: selected) {
                let f = strip.frame
                line += String(format: " strip=%.0f,%.0f,%.0f,%.0f tab=%.0f", f.minX, f.minY, f.width, f.height, strip.tabWidth)
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func collect(_ view: NSView, into list: inout [WKWebView]) {
        if let web = view as? WKWebView { list.append(web); return }
        for child in view.subviews { collect(child, into: &list) }
    }
}
#endif

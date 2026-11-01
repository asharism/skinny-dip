#if os(macOS)
import Foundation

/// Directory in the app bundle that holds `editor.html`, `preview.html`, and related assets.
enum WebBundleResources {
    static func directory() -> URL? {
        guard let root = Bundle.main.resourceURL else { return nil }
        let nested = root.appendingPathComponent("Resources", isDirectory: true)
        if FileManager.default.fileExists(atPath: nested.appendingPathComponent("editor.html").path) {
            return nested
        }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("editor.html").path) {
            return root
        }
        return nil
    }

    static func page(named name: String) -> URL? {
        guard let directory = directory() else { return nil }
        let page = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: page.path) ? page : nil
    }

    /// WebKit needs read access to the whole bundle Resources folder, not only the nested copy.
    static func readAccessRoot() -> URL? {
        Bundle.main.resourceURL
    }
}
#endif

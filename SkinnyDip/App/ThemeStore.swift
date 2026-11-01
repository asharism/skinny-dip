import Combine
import Foundation
import MarkdownCore

@MainActor
final class ThemeStore: ObservableObject {
    static let order = ["paper", "sea-glass", "apricot", "lilac", "ink", "pine", "ember", "plum"]

    @Published private(set) var files: [ThemeFile] = []

    init() {
        files = Self.loadFiles()
    }

    var lightThemes: [ThemeFile] { files.filter { $0.appearance == .light } }
    var darkThemes: [ThemeFile] { files.filter { $0.appearance == .dark } }

    func file(id: String) -> ThemeFile? {
        files.first { $0.id == id }
    }

    func resolved(mode: String, fixed: String, light: String, dark: String, systemIsDark: Bool) -> ResolvedTheme {
        let id = ThemeSelection.resolve(
            mode: mode,
            fixed: fixed,
            light: light,
            dark: dark,
            systemIsDark: systemIsDark,
            available: Set(files.map(\.id))
        )
        if let theme = file(id: id)?.resolve() { return theme }
        if let fallback = files.first?.resolve() { return fallback }
        return Self.fallback.resolve()
    }

    private static func loadFiles() -> [ThemeFile] {
        let directories = [
            Bundle.main.resourceURL?.appendingPathComponent("Resources/themes"),
            Bundle.main.resourceURL?.appendingPathComponent("themes"),
        ].compactMap { $0 }
        for directory in directories {
            let loaded = order.compactMap { id -> ThemeFile? in
                let url = directory.appendingPathComponent("\(id).json")
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(ThemeFile.self, from: data)
            }
            if !loaded.isEmpty { return loaded }
        }
        return [Self.fallback]
    }

    private static let fallback: ThemeFile = {
        let json = """
        {"id":"paper","name":"Paper","appearance":"light","pair":"ink","background":"#efe9df","foreground":"#2b2b2b","cursor":"#a84d26","cursorText":"#efe9df","selectionBackground":"#f0ddd2","selectionForeground":"#2b2b2b","ansi":["#2b2b2b","#b3261e","#55672a","#8a6a00","#943f1b","#3c5a78","#2b6797","#f4f4f2","#8f8a84","#b3261e","#55672a","#8a6a00","#943f1b","#3c5a78","#2b6797","#ffffff"],"skinnyDip":{"windowGradient":["#efe9df","#e4ecee"],"muted":"#67625c","accent":"#a84d26"}}
        """
        return (try? JSONDecoder().decode(ThemeFile.self, from: Data(json.utf8)))
            ?? (try! JSONDecoder().decode(ThemeFile.self, from: Data(json.utf8)))
    }()
}

import Testing
@testable import MarkdownCore

struct ThemeSelectionTests {
    private let available: Set<String> = ["paper", "ink", "plum"]

    @Test func systemFollowsAppearance() {
        #expect(ThemeSelection.resolve(mode: "system", fixed: "plum", light: "paper", dark: "ink", systemIsDark: false, available: available) == "paper")
        #expect(ThemeSelection.resolve(mode: "system", fixed: "plum", light: "paper", dark: "ink", systemIsDark: true, available: available) == "ink")
    }

    @Test func fixedIgnoresSystemAppearance() {
        #expect(ThemeSelection.resolve(mode: "fixed", fixed: "plum", light: "paper", dark: "ink", systemIsDark: false, available: available) == "plum")
        #expect(ThemeSelection.resolve(mode: "fixed", fixed: "plum", light: "paper", dark: "ink", systemIsDark: true, available: available) == "plum")
    }

    @Test func unknownIdFallsBack() {
        #expect(ThemeSelection.resolve(mode: "system", fixed: "paper", light: "missing", dark: "ink", systemIsDark: false, available: available) == "paper")
        #expect(ThemeSelection.resolve(mode: "system", fixed: "paper", light: "paper", dark: "missing", systemIsDark: true, available: available) == "ink")
        #expect(ThemeSelection.resolve(mode: "fixed", fixed: "nope", light: "paper", dark: "ink", systemIsDark: true, available: available) == "paper")
    }
}

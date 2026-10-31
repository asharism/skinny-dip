import Foundation
import Testing
import MarkdownCore
@testable import SkinnyDip

struct RenderSettingsTests {
    private let suite = "SkinnyDipTests.\(UUID().uuidString)"

    @Test func unsetKeysGiveTheDefaultOptions() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(RenderSettings.options(from: defaults) == .default)
    }

    @Test func eachToggleMapsToItsOption() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: RenderSettings.demotesHeadings)
        defaults.set(false, forKey: RenderSettings.bordersTables)
        defaults.set(false, forKey: RenderSettings.newlinesAsBreaks)

        #expect(RenderSettings.options(from: defaults) == .plain)

        defaults.set(true, forKey: RenderSettings.bordersTables)
        #expect(RenderSettings.options(from: defaults)
            == RenderOptions(demotesHeadings: false, bordersTables: true, newlinesAsBreaks: false))
    }
}

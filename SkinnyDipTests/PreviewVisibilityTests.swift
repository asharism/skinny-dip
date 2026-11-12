import Foundation
import Testing
@testable import SkinnyDip

struct PreviewVisibilityTests {
    private let suite = "SkinnyDipTests.\(UUID().uuidString)"

    @Test func newTabFollowsSettingOn() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreviewVisibility.inNewDocuments)

        #expect(PreviewVisibility.initial(from: defaults))
    }

    @Test func newTabFollowsSettingOff() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: PreviewVisibility.inNewDocuments)

        #expect(!PreviewVisibility.initial(from: defaults))
    }

    @Test func unsetSettingShowsThePreview() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(PreviewVisibility.initial(from: defaults))
    }

    @Test func migratesHiddenShowPreviewToSettingOff() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: PreviewVisibility.legacyShowPreview)

        PreviewVisibility.migrate(defaults)

        #expect(defaults.object(forKey: PreviewVisibility.inNewDocuments) as? Bool == false)
        #expect(defaults.object(forKey: PreviewVisibility.legacyShowPreview) == nil)
        #expect(!PreviewVisibility.initial(from: defaults))
    }

    @Test func migrationDropsShownLegacyKeyAndKeepsDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreviewVisibility.legacyShowPreview)

        PreviewVisibility.migrate(defaults)

        #expect(defaults.object(forKey: PreviewVisibility.inNewDocuments) == nil)
        #expect(defaults.object(forKey: PreviewVisibility.legacyShowPreview) == nil)
        #expect(PreviewVisibility.initial(from: defaults))
    }

    @Test func migrationLeavesDefaultWhenOldKeyAbsent() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        PreviewVisibility.migrate(defaults)

        #expect(defaults.object(forKey: PreviewVisibility.inNewDocuments) == nil)
        #expect(PreviewVisibility.initial(from: defaults))
    }

    @Test func migrationNeverOverridesAnExplicitSetting() throws {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PreviewVisibility.inNewDocuments)
        defaults.set(false, forKey: PreviewVisibility.legacyShowPreview)

        PreviewVisibility.migrate(defaults)

        #expect(PreviewVisibility.initial(from: defaults))
        #expect(defaults.object(forKey: PreviewVisibility.legacyShowPreview) == nil)
    }
}

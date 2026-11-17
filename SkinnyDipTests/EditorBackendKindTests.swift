import Foundation
import Testing
@testable import SkinnyDip

/// The Editor Backend is read once at launch from `editorBackend` (ADR-0010).
struct EditorBackendKindTests {
    private func defaults() -> UserDefaults {
        let name = "SkinnyDipTests.editorBackend.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func missingSettingMeansNative() {
        #expect(EditorBackendKind.stored(in: defaults()) == .native)
    }

    @Test func unknownSettingMeansNative() {
        let defaults = defaults()
        defaults.set("vim", forKey: EditorBackendKind.defaultsKey)
        #expect(EditorBackendKind.stored(in: defaults) == .native)
    }

    @Test func storedCodeMirrorIsKept() {
        let defaults = defaults()
        defaults.set("codeMirror", forKey: EditorBackendKind.defaultsKey)
        #expect(EditorBackendKind.stored(in: defaults) == .codeMirror)
    }

    /// ADR-0010 Outcome: native is listed first, CodeMirror is marked legacy.
    @Test func pickerListsNativeFirstAndCodeMirrorAsLegacy() {
        #expect(EditorBackendKind.allCases == [.native, .codeMirror])
        #expect(EditorBackendKind.native.title == "Native")
        #expect(EditorBackendKind.codeMirror.title == "CodeMirror (legacy)")
    }

    @Test func roundTrip() {
        let defaults = defaults()
        for kind in EditorBackendKind.allCases {
            kind.store(in: defaults)
            #expect(defaults.string(forKey: "editorBackend") == kind.rawValue)
            #expect(EditorBackendKind.stored(in: defaults) == kind)
        }
    }
}

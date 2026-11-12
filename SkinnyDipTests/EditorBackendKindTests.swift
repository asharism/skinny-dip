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

    @Test func missingValueIsCodeMirror() {
        #expect(EditorBackendKind.stored(in: defaults()) == .codeMirror)
    }

    @Test func unknownValueIsCodeMirror() {
        let defaults = defaults()
        defaults.set("monaco", forKey: EditorBackendKind.defaultsKey)
        #expect(EditorBackendKind.stored(in: defaults) == .codeMirror)
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

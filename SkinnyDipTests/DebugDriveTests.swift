#if os(macOS) && DEBUG
import AppKit
import Foundation
import Testing
@testable import SkinnyDip

/// The drive script: parsing, and its steps against a hosted editor.
@MainActor
struct DebugDriveTests {
    @Test func parsesObjectAndBareArray() throws {
        let object = #"{"quit": true, "steps": [{"step": "setText", "text": "a"}, {"step": "select", "location": 1, "length": 2}]}"#
        let script = try DriveScript.parse(Data(object.utf8))
        #expect(script.quit)
        #expect(script.steps == [DriveStep(step: "setText", text: "a"), DriveStep(step: "select", location: 1, length: 2)])

        let bare = try DriveScript.parse(Data(#"[{"step": "wait", "ms": 5}]"#.utf8))
        #expect(!bare.quit)
        #expect(bare.steps.first?.ms == 5)
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: (any Error).self) { try DriveScript.parse(Data("nope".utf8)) }
    }

    @Test func resolvesKeysAndModifiers() {
        #expect(DriveKey.resolve("b")?.keyCode == 11)
        #expect(DriveKey.resolve("]")?.keyCode == 30)
        #expect(DriveKey.resolve("up")?.keyCode == 126)
        #expect(DriveKey.resolve("nonsense") == nil)
        #expect(DriveKey.flags(["cmd", "shift"]) == [.command, .shift])
        #expect(DriveKey.flags(["hyper"]) == nil)
    }

    private func run(_ harness: NativeEditorHarness, _ steps: [DriveStep]) async -> DriveResult {
        let window = harness.textView.window
        let executor = DriveExecutor { window }
        // The harness turns off per-event undo groups, so hold one open for the whole run.
        harness.textView.undoManager?.beginUndoGrouping()
        await executor.run(DriveScript(steps: steps))
        harness.textView.undoManager?.endUndoGrouping()
        return executor.result
    }

    @Test func setTextSelectAndSelectorRunOnTheEditor() async throws {
        let harness = NativeEditorHarness(text: "")
        defer { harness.teardown() }
        let result = await run(harness, [
            DriveStep(step: "setText", text: "one\ntwo"),
            DriveStep(step: "select", location: 0, length: 3),
            DriveStep(step: "selector", selector: "selectLine:"),
            DriveStep(step: "dumpText"),
        ])
        #expect(result.ok, "\(result)")
        #expect(result.state == "done")
        #expect(result.steps[0].text == "one\ntwo")
        #expect(result.steps[1].selection == [0, 3])
        #expect(result.steps[3].selection == [0, 4])
        #expect(harness.textView.string == "one\ntwo")
    }

    @Test func keyStepGoesThroughKeyEquivalent() async throws {
        let harness = NativeEditorHarness(text: "one\ntwo")
        defer { harness.teardown() }
        let result = await run(harness, [
            DriveStep(step: "select", location: 1, length: 0),
            DriveStep(step: "key", key: "l", modifiers: ["command"]),
        ])
        #expect(result.ok, "\(result)")
        #expect(result.steps[1].selection == [0, 4])
    }

    @Test func failuresAreReportedPerStep() async throws {
        let harness = NativeEditorHarness(text: "abc")
        defer { harness.teardown() }
        let result = await run(harness, [
            DriveStep(step: "select", location: 2, length: 10),
            DriveStep(step: "bogus"),
            DriveStep(step: "menu", menu: "Nope", item: "Nothing"),
            DriveStep(step: "dumpText"),
        ])
        #expect(!result.ok)
        #expect(result.steps.map(\.ok) == [false, false, false, true])
        #expect(result.steps[1].error?.contains("unknown step") == true)
    }

    @Test func pasteboardIsRestoredAfterTheRun() async throws {
        let harness = NativeEditorHarness(text: "x")
        defer { harness.teardown() }
        let before = NSPasteboard.general.string(forType: .string)
        let result = await run(harness, [DriveStep(step: "setPasteboard", text: "https://example.com/drive-test")])
        #expect(result.ok)
        #expect(NSPasteboard.general.string(forType: .string) == before)
    }
}
#endif

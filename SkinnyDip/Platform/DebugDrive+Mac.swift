#if os(macOS) && DEBUG
import AppKit

/// Debug builds only: the in-app drive script. Synthetic keyboard input and menu clicks from
/// outside the process never reach the editor, so an agent hands the app a JSON list of steps
/// and the app runs them on its own front document's editor, then writes what happened.
///
/// Launch with `SKINNYDIP_DRIVE=<steps>.json` (inside the sandbox container's tmp); `scripts/drive.sh`
/// does this. Results go to `<steps>.json.result.json`. Format: `.claude/skills/drive-app/SKILL.md`.

/// One step. `step` names the action; the other fields belong to specific actions.
struct DriveStep: Codable, Equatable {
    var step: String
    var text: String?
    var location: Int?
    var length: Int?
    var menu: String?
    var item: String?
    var key: String?
    var modifiers: [String]?
    var selector: String?
    var ms: Int?
    var path: String?
}

struct DriveScript: Codable, Equatable {
    var steps: [DriveStep]
    var quit: Bool = false

    private enum CodingKeys: String, CodingKey { case steps, quit }

    init(steps: [DriveStep], quit: Bool = false) {
        self.steps = steps
        self.quit = quit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decode([DriveStep].self, forKey: .steps)
        quit = try container.decodeIfPresent(Bool.self, forKey: .quit) ?? false
    }

    /// Accepts `{"steps": [...], "quit": true}` or a bare array of steps.
    static func parse(_ data: Data) throws -> DriveScript {
        let decoder = JSONDecoder()
        if let script = try? decoder.decode(DriveScript.self, from: data) { return script }
        return DriveScript(steps: try decoder.decode([DriveStep].self, from: data))
    }
}

struct DriveStepResult: Codable, Equatable {
    var index: Int
    var step: String
    var ok: Bool
    var error: String?
    var note: String?
    var text: String?
    var selection: [Int]?
    var keyWindow: Bool?
    var firstResponder: String?
}

struct DriveResult: Codable, Equatable {
    var state = "running"
    var ok = true
    var error: String?
    var steps: [DriveStepResult] = []
}

enum DriveKey {
    static let known = ["command", "cmd", "shift", "option", "alt", "control", "ctrl"]

    static func flags(_ names: [String]) -> NSEvent.ModifierFlags? {
        var flags: NSEvent.ModifierFlags = []
        for name in names {
            switch name.lowercased() {
            case "command", "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "option", "alt": flags.insert(.option)
            case "control", "ctrl": flags.insert(.control)
            default: return nil
            }
        }
        return flags
    }

    /// The characters and key code for a key name: a single character, or `up` `down` `left` `right`
    /// `return` `tab` `escape` `delete` `space`. Key codes are ANSI-layout; AppKit matches key
    /// equivalents on characters.
    static func resolve(_ name: String) -> (characters: String, keyCode: UInt16)? {
        func special(_ code: UInt16, _ scalar: Int) -> (String, UInt16) {
            (String(UnicodeScalar(scalar)!), code)
        }
        switch name.lowercased() {
        case "up": return special(126, NSUpArrowFunctionKey)
        case "down": return special(125, NSDownArrowFunctionKey)
        case "left": return special(123, NSLeftArrowFunctionKey)
        case "right": return special(124, NSRightArrowFunctionKey)
        case "return", "enter": return ("\r", 36)
        case "tab": return ("\t", 48)
        case "escape", "esc": return ("\u{1B}", 53)
        case "delete", "backspace": return ("\u{7F}", 51)
        case "space": return (" ", 49)
        default: break
        }
        guard name.count == 1 else { return nil }
        let codes: [Character: UInt16] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
            "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        ]
        let character = name.lowercased().first!
        return (String(character), codes[character] ?? 0)
    }
}

/// Runs a script. `window` finds the document window each step acts on, so tests can aim it at a harness.
@MainActor
final class DriveExecutor {
    private let window: () -> NSWindow?
    private(set) var result = DriveResult()
    private var savedPasteboard: String??
    var onUpdate: ((DriveResult) -> Void)?

    init(window: @escaping () -> NSWindow?) {
        self.window = window
    }

    func run(_ script: DriveScript) async {
        for (index, step) in script.steps.enumerated() {
            var record = DriveStepResult(index: index, step: step.step, ok: true)
            do {
                try await perform(step, record: &record)
            } catch {
                record.ok = false
                record.error = "\(error)"
                result.ok = false
            }
            observe(into: &record)
            result.steps.append(record)
            onUpdate?(result)
        }
        restorePasteboard()
        result.state = "done"
        onUpdate?(result)
    }

    struct Failure: Error, CustomStringConvertible {
        var description: String
        init(_ description: String) { self.description = description }
    }

    private func editor() throws -> (window: NSWindow, textView: NativeEditorTextView) {
        guard let window = window() else { throw Failure("no document window") }
        guard let textView = Self.findEditor(in: window) else { throw Failure("no editor in the window") }
        return (window, textView)
    }

    static func findEditor(in window: NSWindow) -> NativeEditorTextView? {
        func find(_ view: NSView) -> NativeEditorTextView? {
            if let textView = view as? NativeEditorTextView { return textView }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        return window.contentView.flatMap(find)
    }

    private func observe(into record: inout DriveStepResult) {
        guard let window = window() else { return }
        record.keyWindow = window.isKeyWindow
        record.firstResponder = window.firstResponder.map { String(describing: type(of: $0)) }
        if let textView = Self.findEditor(in: window) {
            record.text = textView.string
            let range = textView.selectedRange()
            record.selection = [range.location, range.length]
        }
    }

    private func focusEditor() throws {
        let (window, textView) = try editor()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(textView) else { throw Failure("editor refused first responder") }
    }

    private func perform(_ step: DriveStep, record: inout DriveStepResult) async throws {
        switch step.step {
        case "setText":
            try focusEditor()
            let textView = try editor().textView
            guard let text = step.text else { throw Failure("setText needs `text`") }
            let whole = NSRange(location: 0, length: (textView.string as NSString).length)
            textView.insertText(text, replacementRange: whole)
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        case "select":
            let textView = try editor().textView
            guard let location = step.location, let length = step.length else { throw Failure("select needs `location` and `length`") }
            let range = NSRange(location: location, length: length)
            guard NSMaxRange(range) <= (textView.string as NSString).length else { throw Failure("range outside the text") }
            textView.setSelectedRange(range)
        case "focusEditor":
            try focusEditor()
        case "focusPreview":
            let window = try editor().window
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            guard let preview = Self.findPreview(in: window) else { throw Failure("no Preview in the window (hidden?)") }
            guard window.makeFirstResponder(preview) else { throw Failure("Preview refused first responder") }
        case "menu":
            try focusEditor()
            guard let menu = step.menu, let item = step.item else { throw Failure("menu needs `menu` and `item`") }
            record.note = try performMenu(menu, item)
        case "key":
            try focusEditor()
            guard let key = step.key else { throw Failure("key needs `key`") }
            record.note = try sendKey(key, modifiers: step.modifiers ?? [])
        case "selector":
            try focusEditor()
            guard let name = step.selector else { throw Failure("selector needs `selector`") }
            let selector = Selector(name)
            if NSApp.sendAction(selector, to: nil, from: nil) {
                record.note = "handled"
            } else if let window = window(), window.firstResponder?.tryToPerform(selector, with: nil) == true {
                record.note = "handled by the window's responder chain (window not key)"
            } else {
                throw Failure("no responder handled \(name)")
            }
        case "setPasteboard":
            guard let text = step.text else { throw Failure("setPasteboard needs `text`") }
            if savedPasteboard == nil { savedPasteboard = .some(NSPasteboard.general.string(forType: .string)) }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case "wait":
            try await Task.sleep(for: .milliseconds(step.ms ?? 100))
        case "snapshot":
            guard let path = step.path else { throw Failure("snapshot needs `path`") }
            await DebugSnapshot.capture(to: URL(fileURLWithPath: path))
            guard FileManager.default.fileExists(atPath: path) else { throw Failure("no snapshot written to \(path)") }
        case "dumpText":
            break
        default:
            throw Failure("unknown step \(step.step)")
        }
    }

    private func performMenu(_ menuTitle: String, _ itemTitle: String) throws -> String {
        guard let main = NSApp.mainMenu else { throw Failure("no main menu") }
        guard let top = main.items.first(where: { $0.title == menuTitle }), let submenu = top.submenu else {
            throw Failure("no menu \(menuTitle); have \(main.items.map(\.title))")
        }
        submenu.update()
        guard let index = submenu.items.firstIndex(where: { $0.title == itemTitle }) else {
            throw Failure("no item \(itemTitle) in \(menuTitle); have \(submenu.items.map(\.title))")
        }
        let item = submenu.items[index]
        guard item.isEnabled else { throw Failure("\(menuTitle) > \(itemTitle) is disabled") }
        submenu.performActionForItem(at: index)
        return "performed \(menuTitle) > \(itemTitle)"
    }

    /// Dispatches as `NSApplication.sendEvent` does for a key down: the window's key equivalents,
    /// then the main menu, then the first responder's `keyDown`.
    private func sendKey(_ name: String, modifiers: [String]) throws -> String {
        guard let flags = DriveKey.flags(modifiers) else { throw Failure("modifiers are \(DriveKey.known)") }
        guard let (characters, keyCode) = DriveKey.resolve(name) else { throw Failure("unknown key \(name)") }
        let window = try editor().window
        let shifted = flags.contains(.shift) ? characters.uppercased() : characters
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: shifted,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        ) else { throw Failure("could not build the key event") }
        if window.performKeyEquivalent(with: event) { return "window.performKeyEquivalent" }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return "mainMenu.performKeyEquivalent" }
        window.firstResponder?.keyDown(with: event)
        return "keyDown to first responder"
    }

    private static func findPreview(in window: NSWindow) -> NSView? {
        func find(_ view: NSView) -> NSView? {
            if view is PreviewWebView, !view.isHiddenOrHasHiddenAncestor { return view }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        return window.contentView.flatMap(find)
    }

    private func restorePasteboard() {
        guard let saved = savedPasteboard else { return }
        NSPasteboard.general.clearContents()
        if let string = saved { NSPasteboard.general.setString(string, forType: .string) }
        savedPasteboard = nil
    }
}

@MainActor
enum DebugDrive {
    private static var task: Task<Void, Never>?

    static func installIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["SKINNYDIP_DRIVE"], !path.isEmpty else { return }
        task = Task { @MainActor in await runFile(URL(fileURLWithPath: path)) }
    }

    private static func runFile(_ url: URL) async {
        let resultURL = URL(fileURLWithPath: url.path + ".result.json")
        func write(_ result: DriveResult) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(result) { try? data.write(to: resultURL, options: .atomic) }
        }
        let script: DriveScript
        do {
            script = try DriveScript.parse(try Data(contentsOf: url))
        } catch {
            write(DriveResult(state: "done", ok: false, error: "cannot read \(url.path): \(error)"))
            return
        }
        // Wait for a document window whose editor is wired up.
        var ready = false
        for _ in 0..<120 {
            if let window = DocumentTabs.frontDocumentTab(), let editor = DriveExecutor.findEditor(in: window),
               editor.editorCoordinator != nil {
                ready = true
                break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard ready else {
            write(DriveResult(state: "done", ok: false, error: "no editor window after 60 s"))
            if script.quit { NSApp.terminate(nil) }
            return
        }
        // Let the window settle (restore, tab strip) before the first step.
        try? await Task.sleep(for: .seconds(1))
        let executor = DriveExecutor { DocumentTabs.frontDocumentTab() }
        executor.onUpdate = { write($0) }
        await executor.run(script)
        if script.quit {
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil)
        }
    }
}
#endif

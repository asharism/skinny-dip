#if os(macOS) && DEBUG
import AppKit
import WebKit

/// An Editor Backend the soak harness (#62) can type into as if a person were typing.
/// Each call is real user input: undo history, the document binding, the Preview and the
/// Scratch Document flush all run as they do for keystrokes. A backend must also call
/// `EditorController.debugTextObserver` whenever it reports a text change, so the harness
/// can time each character. CodeMirror conforms through `debugType` in `editor.js`;
/// the native backend (#64) conforms with `insertText(_:replacementRange:)`.
@MainActor
protocol DebugTypingTarget: AnyObject {
    var debugEditorController: EditorController? { get }
    /// Types `text`, one character per user-input transaction. False if the editor isn't ready.
    func debugType(_ text: String) async -> Bool
}

extension EditorWebView: DebugTypingTarget {
    var debugEditorController: EditorController? { editorCoordinator?.parent.controller }

    func debugType(_ text: String) async -> Bool {
        let length = try? await callAsyncJavaScript(
            "return debugType(text)",
            arguments: ["text": text],
            contentWorld: .page
        )
        return length != nil
    }
}

extension NativeEditorTextView: DebugTypingTarget {
    var debugEditorController: EditorController? { editorCoordinator?.parent.controller }

    /// Types through `insertText(_:replacementRange:)`, the path a key press takes.
    func debugType(_ text: String) async -> Bool {
        guard editorCoordinator != nil else { return false }
        for character in text {
            insertText(String(character), replacementRange: selectedRange())
        }
        return true
    }
}

/// The text the soak harness types: prose with headings, lists, a table and code fences,
/// in the shape of the editor spikes' `SampleDocument`. The same seed gives the same text.
enum SoakScript {
    static func text(seed: UInt64, length: Int) -> String {
        var random = SplitMix64(seed: seed)
        var out = ""
        var number = 1
        while out.count < length {
            out += section(number, random: &random)
            number += 1
        }
        return String(out.prefix(length))
    }

    private static let words = [
        "draft", "reply", "meeting", "notes", "quarter", "plan", "review", "update", "owner",
        "deadline", "status", "budget", "risk", "follow", "team", "customer", "launch", "copy",
        "paste", "table", "summary", "decision", "action", "thanks", "today", "tomorrow",
    ]

    private static func sentence(_ random: inout SplitMix64, words count: Int) -> String {
        var parts: [String] = []
        for index in 0..<count {
            var word = words[Int(random.next() % UInt64(words.count))]
            if index == 0 { word = word.prefix(1).uppercased() + word.dropFirst() }
            switch random.next() % 12 {
            case 0: word = "**\(word)**"
            case 1: word = "*\(word)*"
            case 2: word = "`\(word)`"
            default: break
            }
            parts.append(word)
        }
        return parts.joined(separator: " ") + "."
    }

    private static func section(_ number: Int, random: inout SplitMix64) -> String {
        let heading = number == 1 ? "# Soak draft" : "## Section \(number)"
        let lines = [
            heading,
            "",
            "\(sentence(&random, words: 12)) See [the notes](https://example.com/\(number)). \(sentence(&random, words: 9))",
            "",
            "- \(sentence(&random, words: 4))",
            "- item two with `inline code`",
            "  - nested \(sentence(&random, words: 3))",
            "- [ ] task \(number)",
            "",
            "1. \(sentence(&random, words: 5))",
            "2. \(sentence(&random, words: 5))",
            "",
            "| Column A | Column B |",
            "| --- | --- |",
            "| \(number) | \(words[Int(random.next() % UInt64(words.count))]) |",
            "",
            "```swift",
            "let section = \(number)",
            "print(\"section \\(section)\")",
            "```",
            "",
            "> \(sentence(&random, words: 8))",
            "",
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Nearest-rank percentiles of typing latency, in milliseconds.
struct LatencyStats: Codable, Equatable {
    var count: Int
    var p50: Double
    var p95: Double
    var max: Double

    init(_ samples: [Double]) {
        let sorted = samples.sorted()
        count = sorted.count
        func rank(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            let index = Int((p / 100 * Double(sorted.count)).rounded(.up)) - 1
            return sorted[Swift.max(0, Swift.min(sorted.count - 1, index))]
        }
        p50 = rank(50)
        p95 = rank(95)
        max = sorted.last ?? 0
    }
}

/// Debug builds only: the in-app soak driver (#62). Launch with `SKINNYDIP_SOAK=<log.json>`
/// (inside the sandbox container); `scripts/soak.sh` does this and samples memory from outside.
///
/// - `SKINNYDIP_SOAK_MINUTES` typing minutes (default 30), `SKINNYDIP_SOAK_IDLE_MINUTES` (default 10)
/// - `SKINNYDIP_SOAK_TABS` (default 3), `SKINNYDIP_SOAK_SEED` (default 1)
/// - `SKINNYDIP_SOAK_NO_PREVIEW=1`: no Preview web view and no Preview rendering
/// - `SKINNYDIP_SOAK_NO_HISTORY_EXPORT=1`: Scratch flushes skip `exportState()`; history is
///   exported only on close and quit
@MainActor
enum DebugSoak {
    private static let environment = ProcessInfo.processInfo.environment
    static let hidesPreview = environment["SKINNYDIP_SOAK_NO_PREVIEW"] == "1"
    static let skipsHistoryExport = environment["SKINNYDIP_SOAK_NO_HISTORY_EXPORT"] == "1"

    private static var runner: SoakRunner?

    static func installIfRequested() {
        guard let path = environment["SKINNYDIP_SOAK"], !path.isEmpty else { return }
        func number(_ key: String, _ fallback: Double) -> Double {
            environment[key].flatMap(Double.init) ?? fallback
        }
        let config = SoakRunner.Config(
            typingMinutes: number("SKINNYDIP_SOAK_MINUTES", 30),
            idleMinutes: number("SKINNYDIP_SOAK_IDLE_MINUTES", 10),
            tabs: Int(number("SKINNYDIP_SOAK_TABS", 3)),
            seed: UInt64(number("SKINNYDIP_SOAK_SEED", 1)),
            noPreview: hidesPreview,
            noHistoryExport: skipsHistoryExport
        )
        let runner = SoakRunner(config: config, log: URL(fileURLWithPath: path))
        self.runner = runner
        Task { @MainActor in await runner.run() }
    }
}

@MainActor
final class SoakRunner {
    struct Config: Codable {
        var typingMinutes: Double
        var idleMinutes: Double
        var tabs: Int
        var seed: UInt64
        var noPreview: Bool
        var noHistoryExport: Bool
        var charactersPerSecond = 8.0
        var pauseEvery = 40
        var pauseSeconds = 1.2
    }

    struct Process: Codable {
        var tab: Int
        var role: String
        var pid: Int32
    }

    struct Minute: Codable {
        var minute: Int
        var phase: String
        var tab: Int?
        var characters: Int
        var timeouts: Int
        var latencyMs: LatencyStats
    }

    struct Log: Codable {
        var config: Config
        var state = "starting"
        var startedAt = Date()
        var processes: [Process] = []
        var minutes: [Minute] = []
        var typedCharacters = 0
        var overall = LatencyStats([])
        var error: String?
    }

    private let config: Config
    private let url: URL
    private var log: Log
    private let clock = ContinuousClock()
    private var activity: NSObjectProtocol?

    init(config: Config, log url: URL) {
        self.config = config
        self.url = url
        self.log = Log(config: config)
    }

    func run() async {
        // Keep App Nap from stretching the typing schedule while the window is behind others.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Skinny soak harness"
        )
        write()
        guard let first = await waitForTarget(in: nil) else {
            return fail("no editor window after launch")
        }
        let host = first.window
        for _ in 1..<max(1, config.tabs) {
            let before = Set(documentWindows().map(ObjectIdentifier.init))
            DocumentTabs.newDocument(in: host)
            try? await Task.sleep(for: .milliseconds(500))
            guard let window = documentWindows().first(where: { !before.contains(ObjectIdentifier($0)) }),
                  await waitForTarget(in: window) != nil
            else { return fail("new Tab never got an editor") }
        }
        // Give each web view a moment to finish loading before taking process IDs.
        try? await Task.sleep(for: .seconds(3))
        let tabs = tabWindows(of: host)
        log.processes = processes(in: tabs)
        log.state = "typing"
        write()

        let script = Array(SoakScript.text(
            seed: config.seed,
            length: Int(config.typingMinutes * 60 * config.charactersPerSecond) + 1_000
        ))
        var cursor = 0
        var all: [Double] = []
        let step = Duration.seconds(1 / config.charactersPerSecond)
        let typingMinutes = Int(config.typingMinutes.rounded(.up))
        for minute in 0..<typingMinutes {
            let tabIndex = minute % max(1, tabs.count)
            let window = tabs[tabIndex]
            window.tabGroup?.selectedWindow = window
            guard let target = typingTarget(in: window) else { return fail("Tab \(tabIndex + 1) lost its editor") }
            let end = clock.now + .seconds(min(60, (config.typingMinutes - Double(minute)) * 60))
            var samples: [Double] = []
            var timeouts = 0
            var deadline = clock.now
            while clock.now < end, cursor < script.count {
                if cursor > 0, cursor % config.pauseEvery == 0 {
                    deadline += .seconds(config.pauseSeconds)
                }
                try? await Task.sleep(until: deadline, clock: .continuous)
                if let latency = await type(String(script[cursor]), into: target) {
                    samples.append(latency)
                } else {
                    timeouts += 1
                }
                cursor += 1
                deadline = max(deadline + step, clock.now)
            }
            all += samples
            log.typedCharacters = cursor
            log.overall = LatencyStats(all)
            log.minutes.append(Minute(
                minute: minute + 1,
                phase: "typing",
                tab: tabIndex + 1,
                characters: samples.count + timeouts,
                timeouts: timeouts,
                latencyMs: LatencyStats(samples)
            ))
            write()
        }

        log.state = "idle"
        write()
        let idleMinutes = Int(config.idleMinutes.rounded(.up))
        for minute in 0..<idleMinutes {
            try? await Task.sleep(for: .seconds(min(60, (config.idleMinutes - Double(minute)) * 60)))
            log.minutes.append(Minute(
                minute: typingMinutes + minute + 1,
                phase: "idle",
                tab: nil,
                characters: 0,
                timeouts: 0,
                latencyMs: LatencyStats([])
            ))
            write()
        }
        log.state = "done"
        write()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    /// Milliseconds from dispatch until `EditorController` hears the change; nil on a 2 s timeout.
    private func type(_ character: String, into target: DebugTypingTarget) async -> Double? {
        guard let controller = target.debugEditorController else { return nil }
        let waiter = Waiter()
        let start = clock.now
        let result: Duration? = await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            controller.debugTextObserver = { [clock] _ in waiter.finish(clock.now - start) }
            waiter.timeout = Task { @MainActor in
                _ = await target.debugType(character)
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                waiter.finish(nil)
            }
        }
        controller.debugTextObserver = nil
        guard let result else { return nil }
        return Double(result.components.attoseconds) / 1e15 + Double(result.components.seconds) * 1000
    }

    @MainActor
    private final class Waiter {
        var continuation: CheckedContinuation<Duration?, Never>?
        var timeout: Task<Void, Never>?
        func finish(_ value: Duration?) {
            guard let continuation else { return }
            self.continuation = nil
            timeout?.cancel()
            continuation.resume(returning: value)
        }
    }

    private func documentWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.tabbingIdentifier == "SkinnyDipDocument" && $0.isVisible }
    }

    private func tabWindows(of host: NSWindow) -> [NSWindow] {
        host.tabGroup?.windows ?? [host]
    }

    private func waitForTarget(in window: NSWindow?) async -> (window: NSWindow, target: DebugTypingTarget)? {
        for _ in 0..<120 {
            let candidates = window.map { [$0] } ?? documentWindows()
            for candidate in candidates {
                if let target = typingTarget(in: candidate), await target.debugType("") {
                    return (candidate, target)
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    private func typingTarget(in window: NSWindow) -> DebugTypingTarget? {
        func find(_ view: NSView) -> DebugTypingTarget? {
            if let target = view as? DebugTypingTarget { return target }
            for child in view.subviews {
                if let found = find(child) { return found }
            }
            return nil
        }
        return window.contentView.flatMap(find)
    }

    /// Which WebContent process belongs to which Tab's Editor or Preview, so the sampler can label them.
    private func processes(in tabs: [NSWindow]) -> [Process] {
        var result: [Process] = []
        for (index, window) in tabs.enumerated() {
            var webViews: [WKWebView] = []
            func collect(_ view: NSView) {
                if let web = view as? WKWebView { webViews.append(web); return }
                view.subviews.forEach(collect)
            }
            window.contentView.map(collect)
            for web in webViews {
                guard let pid = Self.pid(web, "_webProcessIdentifier") else { continue }
                result.append(Process(tab: index + 1, role: web is DebugTypingTarget ? "editor" : "preview", pid: pid))
            }
            // WebKit's shared helpers, when the SPI answers. The sampler cross-checks them.
            if index == 0, let web = webViews.first {
                if let pid = Self.pid(web, "_gpuProcessIdentifier") {
                    result.append(Process(tab: 0, role: "gpu", pid: pid))
                }
                if let pid = Self.pid(web.configuration.websiteDataStore, "_networkProcessIdentifier")
                    ?? Self.pid(web.configuration.processPool, "_networkProcessIdentifier") {
                    result.append(Process(tab: 0, role: "networking", pid: pid))
                }
            }
        }
        return result
    }

    private static func pid(_ object: NSObject, _ key: String) -> Int32? {
        guard object.responds(to: NSSelectorFromString(key)),
              let pid = (object.value(forKey: key) as? NSNumber)?.int32Value, pid > 0
        else { return nil }
        return pid
    }

    private func fail(_ message: String) {
        log.state = "failed"
        log.error = message
        write()
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(log) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
#endif

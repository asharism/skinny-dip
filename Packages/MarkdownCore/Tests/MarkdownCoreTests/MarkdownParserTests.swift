import Foundation
import Testing
@testable import MarkdownCore

@Test func debouncedRenderCancelsStaleEdits() async throws {
    let parser = MarkdownParser(debounceNanoseconds: 40_000_000)
    let gate = RenderGate()

    await parser.update(source: "# First", options: .default) { html in
        Task { await gate.record(html) }
    }
    await parser.update(source: "# Second", options: .default) { html in
        Task { await gate.record(html) }
    }

    try await Task.sleep(nanoseconds: 120_000_000)
    let rendered = await gate.values
    #expect(rendered.count == 1)
    #expect(rendered[0].contains("<h"))
    #expect(rendered[0].contains("Second"))
    #expect(!rendered[0].contains("First"))
}

@Test func debounceWaitsBeforeRendering() async throws {
    let parser = MarkdownParser(debounceNanoseconds: 60_000_000)
    let gate = RenderGate()

    await parser.update(source: "Hello", options: .default) { html in
        Task { await gate.record(html) }
    }

    try await Task.sleep(nanoseconds: 20_000_000)
    #expect(await gate.values.isEmpty)

    try await Task.sleep(nanoseconds: 80_000_000)
    #expect(await gate.values.count == 1)
}

private actor RenderGate {
    private(set) var values: [String] = []

    func record(_ html: String) {
        values.append(html)
    }
}

#if DEBUG
import Foundation
import Testing
@testable import SkinnyDip

/// The soak harness (#62): its typing script and latency summary.
struct DebugSoakTests {
    @Test func scriptIsTheSameForTheSameSeed() {
        let first = SoakScript.text(seed: 42, length: 5_000)
        let second = SoakScript.text(seed: 42, length: 5_000)
        #expect(first == second)
        #expect(first.count == 5_000)
    }

    @Test func differentSeedsGiveDifferentScripts() {
        #expect(SoakScript.text(seed: 1, length: 2_000) != SoakScript.text(seed: 2, length: 2_000))
    }

    @Test func scriptContainsEveryMarkdownConstruct() {
        let text = SoakScript.text(seed: 7, length: 3_000)
        let lines = text.components(separatedBy: "\n")
        #expect(lines.contains { $0.hasPrefix("# ") || $0.hasPrefix("## ") }, "heading")
        #expect(lines.contains { $0.hasPrefix("- ") }, "bullet list")
        #expect(lines.contains { $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }, "numbered list")
        #expect(lines.contains { $0.hasPrefix("| --- |") }, "table delimiter row")
        #expect(lines.contains { $0.hasPrefix("```") }, "code fence")
        #expect(text.contains("**"), "strong")
        #expect(text.contains("]("), "link")
    }

    @Test func latencyPercentilesUseNearestRank() {
        let samples = (1...100).map(Double.init).shuffled()
        let stats = LatencyStats(samples)
        #expect(stats.count == 100)
        #expect(stats.p50 == 50)
        #expect(stats.p95 == 95)
        #expect(stats.max == 100)
    }

    @Test func latencyOfASmallSample() {
        let stats = LatencyStats([5, 1, 3])
        #expect(stats.p50 == 3)
        #expect(stats.p95 == 5)
        #expect(stats.max == 5)
    }

    @Test func latencyOfNoSamplesIsZero() {
        let stats = LatencyStats([])
        #expect(stats.count == 0)
        #expect(stats.p50 == 0 && stats.p95 == 0 && stats.max == 0)
    }
}
#endif

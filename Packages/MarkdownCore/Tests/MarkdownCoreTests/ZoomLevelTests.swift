import Testing
@testable import MarkdownCore

struct ZoomLevelTests {
    @Test func nextPreviousAndReset() {
        #expect(ZoomLevel.reset().value == 1)
        #expect(ZoomLevel(1).next().value == 1.1)
        #expect(ZoomLevel(1).previous().value == 0.9)
        #expect(ZoomLevel(1.26).value == 1.3)
    }

    @Test func clampsAtTheEnds() {
        #expect(ZoomLevel(0.1).value == 0.5)
        #expect(ZoomLevel(9).value == 2)
        #expect(ZoomLevel(0.5).previous().value == 0.5)
        #expect(ZoomLevel(2).next().value == 2)
    }

    @Test func fifteenStepsUpAndDownHaveNoFloatDrift() {
        var zoom = ZoomLevel(1)
        for _ in 0..<15 { zoom = zoom.next() }
        #expect(zoom.value == 2)
        for _ in 0..<15 { zoom = zoom.previous() }
        #expect(zoom.value == 0.5)

        var around = ZoomLevel.reset()
        for _ in 0..<15 {
            around = around.next()
            around = around.previous()
        }
        #expect(around.value == 1)

        var trip = ZoomLevel(1)
        for _ in 0..<4 { trip = trip.next() }
        for _ in 0..<4 { trip = trip.previous() }
        #expect(trip.value == 1)
    }
}

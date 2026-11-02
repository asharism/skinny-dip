import CoreGraphics
import Testing
@testable import SkinnyDip

/// Where a dragged Tab lands (ui-shell.md §2, Moving Tabs between Windows).
struct TabDropTests {
    // Screen coordinates. The own strip holds 3 Tabs of 100 at y 1000–1038.
    let own = TabDrop.Strip(frame: CGRect(x: 100, y: 1000, width: 306, height: 38), tabWidth: 100, inset: 3, count: 3)
    // Another window lower down, with 2 Tabs.
    let other = TabDrop.Strip(frame: CGRect(x: 600, y: 400, width: 206, height: 38), tabWidth: 100, inset: 3, count: 2)

    @Test func letGoInsideOwnStripReorders() {
        #expect(TabDrop.resolve(point: CGPoint(x: 250, y: 1020), own: own, detachDistance: 40, others: [other]) == .reorder)
    }

    @Test func letGoJustBelowOwnStripStillReorders() {
        #expect(TabDrop.resolve(point: CGPoint(x: 250, y: 975), own: own, detachDistance: 40, others: []) == .reorder)
    }

    @Test func letGoOverAnotherStripJoinsAtTheNearestGap() {
        // x 600+3+100 is the gap between that window's two Tabs.
        #expect(TabDrop.resolve(point: CGPoint(x: 710, y: 420), own: own, detachDistance: 40, others: [other]) == .join(target: 0, slot: 1))
        #expect(TabDrop.resolve(point: CGPoint(x: 605, y: 420), own: own, detachDistance: 40, others: [other]) == .join(target: 0, slot: 0))
        #expect(TabDrop.resolve(point: CGPoint(x: 800, y: 420), own: own, detachDistance: 40, others: [other]) == .join(target: 0, slot: 2))
    }

    @Test func frontmostStripWinsWhenStripsOverlap() {
        let behind = TabDrop.Strip(frame: other.frame, tabWidth: 100, inset: 3, count: 5)
        #expect(TabDrop.resolve(point: CGPoint(x: 650, y: 420), own: own, detachDistance: 40, others: [other, behind]) == .join(target: 0, slot: 0))
    }

    @Test func letGoOnTheDesktopMakesANewWindow() {
        #expect(TabDrop.resolve(point: CGPoint(x: 250, y: 600), own: own, detachDistance: 40, others: [other]) == .newWindow)
    }

    @Test func aWindowsOnlyTabOnTheDesktopDoesNothing() {
        let lone = TabDrop.Strip(frame: own.frame, tabWidth: 100, inset: 3, count: 1)
        #expect(TabDrop.resolve(point: CGPoint(x: 250, y: 600), own: lone, detachDistance: 40, others: [other]) == .none)
    }

    @Test func aWindowsOnlyTabCanJoinAnotherWindow() {
        let lone = TabDrop.Strip(frame: own.frame, tabWidth: 100, inset: 3, count: 1)
        #expect(TabDrop.resolve(point: CGPoint(x: 700, y: 420), own: lone, detachDistance: 40, others: [other]) == .join(target: 0, slot: 1))
    }
}

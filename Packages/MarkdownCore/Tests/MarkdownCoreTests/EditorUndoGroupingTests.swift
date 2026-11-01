import Testing
import MarkdownCore

struct EditorUndoGroupingTests {
    @Test func groupingIsCoarserThanMarkEditDefault() {
        #expect(EditorUndoGrouping.newGroupDelayMilliseconds > 300)
    }
}

import Foundation
import IthilCore
import Testing

struct TimeSourceTests {
    @Test func fixedTimeSourceNeverMoves() {
        // Tuesday 6 October 2026, 13:50 in Europe/Amsterdam: the design's mock "now".
        let instant = Date(timeIntervalSince1970: 1_791_287_400)
        let source = FixedTimeSource(instant)
        #expect(source.now == instant)
        #expect(source.now == source.now)
    }

    @Test func systemTimeSourceFollowsTheClock() {
        let before = Date()
        let now = SystemTimeSource().now
        #expect(now >= before)
        #expect(now.timeIntervalSince(before) < 5)
    }
}

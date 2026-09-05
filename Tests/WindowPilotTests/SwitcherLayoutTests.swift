import Foundation
import Testing
@testable import WindowPilot

struct SwitcherLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 1000)

    @Test func growsBeyondTwelveRowsUntilEightyPercent() {
        let twelve = SwitcherLayout(rowCount: 12, compact: true, searching: false)
        let twenty = SwitcherLayout(rowCount: 20, compact: true, searching: false)
        #expect(twelve.frame(in: screen).height == 352)
        #expect(twenty.frame(in: screen).height == 576)
        let exact = SwitcherLayout(rowCount: 28, compact: true, searching: false)
        #expect(exact.contentHeight == exact.frame(in: screen).height)
        let overflow = SwitcherLayout(rowCount: 29, compact: true, searching: false)
        #expect(overflow.frame(in: screen).height == 800)
        #expect(overflow.contentHeight > overflow.frame(in: screen).height)
    }

    @Test func searchAndEmptyResultsShrinkWithoutClippingHeader() {
        let all = SwitcherLayout(rowCount: 40, compact: true, searching: false)
        let match = SwitcherLayout(rowCount: 1, compact: true, searching: true)
        let empty = SwitcherLayout(rowCount: 0, compact: true, searching: true)
        #expect(all.frame(in: screen).height == 800)
        #expect(match.frame(in: screen).height == 72)
        #expect(empty.frame(in: screen).height == 88)
        #expect(match.frame(in: screen).midY == all.frame(in: screen).midY)
    }

    @Test func densityAndSearchCountTowardTheSameScreenLimit() {
        let compact = SwitcherLayout(rowCount: 27, compact: true, searching: false)
        let search = SwitcherLayout(rowCount: 27, compact: true, searching: true)
        let roomy = SwitcherLayout(rowCount: 27, compact: false, searching: true)
        #expect(compact.frame(in: screen).height == 772)
        #expect(search.frame(in: screen).height == 800)
        #expect(search.contentHeight == 800)
        #expect(roomy.frame(in: screen).height == 800)
        #expect(roomy.contentHeight > 800)
    }

    @Test func fitsShortAndOffsetDisplays() {
        let layout = SwitcherLayout(rowCount: 100, compact: false, searching: true)
        for bounds in [CGRect(x: -1280, y: 100, width: 1280, height: 700),
                       CGRect(x: 1440, y: -600, width: 500, height: 300)] {
            let frame = layout.frame(in: bounds)
            #expect(frame.height <= bounds.height * 0.8)
            #expect(bounds.contains(frame))
            #expect(frame.midX == bounds.midX)
        }
    }
}

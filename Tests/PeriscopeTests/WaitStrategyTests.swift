import Foundation
import Testing

@testable import Periscope

@Suite("WaitStrategy.parse")
struct WaitStrategyTests {
    @Test func noneOptsOutOfWaiting() {
        #expect(WaitStrategy.parse("none") == WaitStrategy.none)
    }

    @Test func fetchquietIsUnboundedWhenExplicit() {
        #expect(WaitStrategy.parse("fetchquiet") == .fetchquiet(maxMs: nil))
    }

    @Test func fetchquietAcceptsACap() {
        #expect(WaitStrategy.parse("fetchquiet:2000") == .fetchquiet(maxMs: 2000))
    }

    @Test func existingSpellingsStillParse() {
        #expect(WaitStrategy.parse("load") == .load)
        #expect(WaitStrategy.parse("selector:#rso") == .selector("#rso"))
        #expect(WaitStrategy.parse("time:250") == .time(250))
        #expect(WaitStrategy.parse("bogus") == nil)
    }

    @Test func navigateDefaultIsBoundedFetchquiet() {
        #expect(WaitStrategy.navigateDefault == .fetchquiet(maxMs: 5000))
    }
}

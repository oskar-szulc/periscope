import Testing
import Foundation
@testable import Periscope

@Suite("withTimeout")
struct TimeoutTests {
    @Test func returnsTheResultInTime() async throws {
        #expect(try await withTimeout(seconds: 5) { 42 } == 42)
    }

    /// The FoundationModels hang: an operation that never checks for
    /// cancellation must not hold the caller past the deadline.
    @Test func timesOutAnOperationThatIgnoresCancellation() async {
        let start = ContinuousClock.now
        await #expect(throws: PeriscopeError.self) {
            try await withTimeout(seconds: 1) {
                await withCheckedContinuation { c in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { c.resume() }
                }
                return 1
            }
        }
        #expect(ContinuousClock.now - start < .seconds(4))
    }
}

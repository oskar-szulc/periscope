import Testing
import Foundation
@testable import Periscope

@Suite("PeriscopeError")
struct PeriscopeErrorTests {
    @Test func navigationFailedIncludesURL() {
        let error = PeriscopeError.navigationFailed(
            url: "https://example.com", reason: "Could not connect to the server.")
        #expect(error.description
            == "Navigation to https://example.com failed: Could not connect to the server.")
    }

    @Test func navigationFailedWithoutURLOmitsEmptyGap() {
        // Regression: an empty URL used to render "Navigation to  failed: ..."
        let error = PeriscopeError.navigationFailed(url: "", reason: "Page was closed")
        #expect(error.description == "Navigation failed: Page was closed")
        #expect(!error.description.contains("  "))
    }

    @Test func navigationFailedExitCode() {
        let error = PeriscopeError.navigationFailed(url: "https://example.com", reason: "nope")
        #expect(error.exitCode == 2)
    }
}

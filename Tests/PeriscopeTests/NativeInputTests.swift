import Foundation
import Testing

@testable import Periscope

@Suite("native input")
struct NativeInputTests {
    @Test func keyCodesFollowTheUSLayout() {
        #expect(HiddenWindowController.keyCode(for: "a") == (0, false))
        #expect(HiddenWindowController.keyCode(for: "A") == (0, true))
        #expect(HiddenWindowController.keyCode(for: "!") == (18, true))  // shift+1
        #expect(HiddenWindowController.keyCode(for: " ") == (49, false))
        #expect(HiddenWindowController.keyCode(for: "é") == (0, false))  // outside the table
    }
    // Delivery itself (trusted keys and clicks) needs a running AppKit event
    // loop, which `swift test` does not have; it is checked live against a fixture.
}

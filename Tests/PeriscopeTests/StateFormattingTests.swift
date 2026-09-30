import Foundation
import Testing

@testable import Periscope

@Suite("PageState formatting")
struct StateFormattingTests {
    private func state(
        elements: [PageStateElement] = [],
        headings: [PageStateHeading] = [],
        text: String = "Body text",
        truncated: Bool = false
    ) -> PageStateData {
        PageStateData(
            url: "https://example.com/login", title: "Sign In",
            text: text, truncated: truncated, elements: elements, headings: headings)
    }

    @Test func textOutputLeadsWithLocation() {
        let output = TextFormatter().format(.state(state()))
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "URL: https://example.com/login")
        #expect(lines[1] == "Title: Sign In")
    }

    @Test func actionsAreColumnAlignedForReadingSelectorsOff() {
        let output = TextFormatter().format(
            .state(
                state(elements: [
                    PageStateElement(selector: "#user", tag: "input", type: "text"),
                    PageStateElement(selector: "#submit-button", tag: "button", text: "Go"),
                ])))
        #expect(output.contains("Actions (2):"))
        // The short selector is padded to the long one so the columns line up.
        #expect(output.contains("  #user           input[text]"))
        #expect(output.contains("  #submit-button  button  \"Go\""))
    }

    @Test func actionsLeadWithTheirAtIndex() {
        let output = TextFormatter().format(
            .state(
                state(elements: [
                    PageStateElement(index: 12, selector: "#go", tag: "button", text: "Go")
                ])))
        #expect(output.contains("  @12  #go  button"))
    }

    @Test func disabledAndCheckedAreCalledOut() {
        let output = TextFormatter().format(
            .state(
                state(elements: [
                    PageStateElement(selector: "#a", tag: "button", disabled: true),
                    PageStateElement(selector: "#b", tag: "input", type: "checkbox", checked: true),
                ])))
        #expect(output.contains("DISABLED"))
        #expect(output.contains("checked"))
    }

    @Test func labelIsNotRepeatedAsText() {
        let output = TextFormatter().format(
            .state(
                state(elements: [
                    PageStateElement(selector: "#a", tag: "input", label: "Email", text: "Email")
                ])))
        #expect(output.contains("label=\"Email\""))
        // Same string twice on one line would be noise in an agent's context.
        #expect(!output.contains("label=\"Email\" \"Email\""))
    }

    @Test func emptyPageSaysSoRatherThanPrintingAnEmptyHeader() {
        let output = TextFormatter().format(.state(state()))
        #expect(output.contains("Actions: none found"))
        #expect(!output.contains("Actions (0)"))
    }

    @Test func truncationIsFlagged() {
        let output = TextFormatter().format(.state(state(text: "abc", truncated: true)))
        #expect(output.contains("Content: (truncated)"))
    }

    @Test func headingsAreIndentedByLevel() {
        let output = TextFormatter().format(
            .state(
                state(headings: [
                    PageStateHeading(level: 1, text: "Top"),
                    PageStateHeading(level: 3, text: "Deep"),
                ])))
        #expect(output.contains("\n  Top"))
        #expect(output.contains("\n      Deep"))
    }

    @Test func jsonRoundTripsThroughTheCodableType() throws {
        let original = state(
            elements: [PageStateElement(selector: "#a", tag: "a", href: "/x", disabled: nil)],
            headings: [PageStateHeading(level: 2, text: "H")])
        let output = JSONFormatter().format(.state(original))

        let data = Data(output.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed?["ok"] as? Bool == true)

        let nested = try JSONSerialization.data(withJSONObject: parsed?["state"] as Any)
        let decoded = try JSONDecoder().decode(PageStateData.self, from: nested)
        #expect(decoded.url == original.url)
        #expect(decoded.elements.first?.selector == "#a")
        #expect(decoded.elements.first?.href == "/x")
    }
}

@Suite("PageState blocked")
struct StateBlockedTests {
    @Test func blockedIsReportedRightAfterLocation() throws {
        var state = PageStateData(
            url: "https://www.google.com/sorry/index", title: "",
            text: "unusual traffic", truncated: false, elements: [], headings: [])
        state.blocked = "google-captcha"
        let output = TextFormatter().format(.state(state))
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[0] == "URL: https://www.google.com/sorry/index")
        #expect(lines[1] == "Blocked: google-captcha")

        let json = JSONFormatter().format(.state(state))
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let inner = object["state"] as! [String: Any]
        #expect(inner["blocked"] as? String == "google-captcha")
    }

    @Test func unblockedStateOmitsTheLine() {
        let state = PageStateData(
            url: "https://example.com/", title: "Hi",
            text: "", truncated: false, elements: [], headings: [])
        let output = TextFormatter().format(.state(state))
        #expect(!output.contains("Blocked:"))
    }
}

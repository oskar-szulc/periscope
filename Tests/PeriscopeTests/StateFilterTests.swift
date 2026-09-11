import Testing
import Foundation
@testable import Periscope

@Suite("State action filtering")
struct StateFilterTests {
    private func element(_ selector: String, label: String? = nil, text: String? = nil, href: String? = nil) -> PageStateElement {
        PageStateElement(selector: selector, tag: "a", label: label, text: text, href: href)
    }

    private func state(_ elements: [PageStateElement]) -> PageStateData {
        PageStateData(url: "https://example.com/", title: "t", text: "", truncated: false,
                      elements: elements, headings: [])
    }

    @Test func capsActionsAndReportsOmittedCount() throws {
        let many = (1...40).map { element("#a\($0)") }
        let out = try StateFilter.apply(state(many), match: nil, limit: 25)
        #expect(out.elements.count == 25)
        #expect(out.omitted == 15)
    }

    @Test func noCapWhenLimitIsNil() throws {
        let many = (1...40).map { element("#a\($0)") }
        let out = try StateFilter.apply(state(many), match: nil, limit: nil)
        #expect(out.elements.count == 40)
        #expect(out.omitted == nil)
    }

    @Test func matchFiltersAcrossSelectorLabelTextAndHref() throws {
        let s = state([
            element("#searchInput", label: "Search Wikipedia"),
            element("#login", text: "Log in"),
            element("#next", text: "Next", href: "/search?start=10"),
            element("#other", text: "Random"),
        ])
        #expect(try StateFilter.apply(s, match: "search", limit: 25).elements.map(\.selector)
            == ["#searchInput", "#next"])
        #expect(try StateFilter.apply(s, match: "(?i)log in", limit: 25).elements.map(\.selector) == ["#login"])
    }

    @Test func matchAppliesBeforeTheCap() throws {
        var many = (1...40).map { element("#a\($0)") }
        many.append(element("#target", text: "Needle"))
        let out = try StateFilter.apply(state(many), match: "Needle", limit: 25)
        #expect(out.elements.map(\.selector) == ["#target"])
        #expect(out.omitted == nil)
    }

    @Test func invalidRegexIsArgumentError() {
        #expect(throws: PeriscopeError.self) {
            try StateFilter.apply(state([]), match: "(", limit: 25)
        }
    }

    @Test func textOutputMentionsOmitted() throws {
        var s = state((1...3).map { element("#a\($0)") })
        s.omitted = 12
        let out = TextFormatter().format(.state(s))
        #expect(out.contains("Actions (3 of 15):"))
        #expect(out.contains("12 more; use --all or --match <regex>"))
    }
}

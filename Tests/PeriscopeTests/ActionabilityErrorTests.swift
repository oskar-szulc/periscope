import Testing
import Foundation
import ArgumentParser
@testable import Periscope

@Suite("Ambiguity and actionability errors")
struct ActionabilityErrorTests {
    @Test func multipleMatchesListCandidates() {
        let error = PeriscopeError.multipleElementsFound(
            selector: "input[name=search]", count: 2,
            candidates: ["#searchInput  input[search] label=\"Search Wikipedia\"",
                         "#vector-sticky-search-form input  input[search]"])
        let text = error.description
        #expect(text.hasPrefix("Selector 'input[name=search]' matched 2 elements"))
        #expect(text.contains("#searchInput"))
        #expect(text.contains("--first"))
        #expect(error.exitCode == 1)
    }

    @Test func candidatesTravelInThePayload() {
        let payload = ErrorPayload(PeriscopeError.multipleElementsFound(
            selector: "a", count: 3, candidates: ["#x", "#y"]))
        #expect(payload.code == "MULTIPLE_ELEMENTS_FOUND")
        #expect(payload.candidates == ["#x", "#y"])
    }

    @Test func notActionableHasItsOwnCode() {
        let error = PeriscopeError.notActionable(selector: "#go", reason: "disabled")
        #expect(error.wireCode == "ELEMENT_NOT_ACTIONABLE")
        #expect(error.exitCode == 1)
        #expect(error.description == "Element #go is not actionable: disabled")
    }

    @Test func strictIsTheDefaultAndFirstOptsOut() throws {
        let defaults = try GlobalOptions.parse([])
        #expect(defaults.strict == true)
        let first = try GlobalOptions.parse(["--first"])
        #expect(first.strict == false)
    }
}

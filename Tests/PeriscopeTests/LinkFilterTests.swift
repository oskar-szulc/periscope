import Foundation
import Testing

@testable import Periscope

@Suite("Links --match")
struct LinkFilterTests {
    let links = [
        LinkItem(text: "Job A", url: "https://jobs.ashbyhq.com/acme/1111"),
        LinkItem(text: "Board", url: "https://jobs.ashbyhq.com/acme"),
        LinkItem(text: "Images", url: "https://www.google.com/search?tbm=isch"),
    ]

    private func kept(_ pattern: String) throws -> [String] {
        let matches = try RegexFilter.matcher(pattern)
        return links.map(\.url).filter(matches)
    }

    @Test func keepsOnlyURLsMatchingTheRegex() throws {
        #expect(try kept(#"ashbyhq\.com/[^/]+/[0-9a-f]+$"#) == ["https://jobs.ashbyhq.com/acme/1111"])
    }

    @Test func matchIsUnanchoredByDefault() throws {
        #expect(try kept("ashbyhq").count == 2)
    }

    @Test func invalidRegexIsAnArgumentError() {
        #expect(throws: PeriscopeError.self) {
            try kept("(")
        }
    }
}

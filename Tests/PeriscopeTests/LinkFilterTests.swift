import Testing
import Foundation
@testable import Periscope

@Suite("Links --match")
struct LinkFilterTests {
    let links = [
        LinkItem(text: "Job A", url: "https://jobs.ashbyhq.com/acme/1111"),
        LinkItem(text: "Board", url: "https://jobs.ashbyhq.com/acme"),
        LinkItem(text: "Images", url: "https://www.google.com/search?tbm=isch"),
    ]

    @Test func keepsOnlyURLsMatchingTheRegex() throws {
        let kept = try LinkFilter.apply(pattern: #"ashbyhq\.com/[^/]+/[0-9a-f]+$"#, to: links)
        #expect(kept.map(\.url) == ["https://jobs.ashbyhq.com/acme/1111"])
    }

    @Test func matchIsUnanchoredByDefault() throws {
        let kept = try LinkFilter.apply(pattern: "ashbyhq", to: links)
        #expect(kept.count == 2)
    }

    @Test func invalidRegexIsAnArgumentError() {
        #expect(throws: PeriscopeError.self) {
            try LinkFilter.apply(pattern: "(", to: links)
        }
    }
}

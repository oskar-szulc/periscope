import Foundation
import Testing
import WebKit

@testable import Periscope

/// Which element text, state and extract read as the page's content.
@Suite("main content root")
struct MainContentTests {
    @MainActor private func root(_ body: String) async throws -> String? {
        let page = WebPage()
        for try await _ in page.load(html: "<html><body>\(body)</body></html>", baseURL: URL(string: "https://x.test/")!) {}
        return try await page.callJavaScript("var r = \(PageSummarizer.mainContentExpr); return r.id || r.tagName")
            as? String
    }

    @Test @MainActor func theMainWithMostTextNotTheFirst() async throws {
        // Next.js: an empty shell <main> ahead of the real one (echojobs.io).
        #expect(try await root("<main id='shell'></main><main id='real'><p>the jobs</p></main>") == "real")
    }

    @Test @MainActor func aLoneArticleButNotTheFirstOfSeveral() async throws {
        #expect(try await root("<article id='post'><p>story</p></article>") == "post")
        // A listing page: articles are cards, the content is the page (books.toscrape).
        #expect(try await root("<article>one</article><article>two</article>") == "BODY")
    }
}

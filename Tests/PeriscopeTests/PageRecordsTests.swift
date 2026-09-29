import Testing
import Foundation
import WebKit
@testable import Periscope

/// Runs `PageRecords.script` in a real WebKit page, the only place its DOM
/// heuristics mean anything.
@MainActor
private func records(_ body: String, head: String = "", from: String? = nil,
                     items: String? = nil) async throws -> [String: Any] {
    let page = WebPage()
    let html = "<html><head><title>T</title>\(head)</head><body>\(body)</body></html>"
    for try await _ in page.load(html: html, baseURL: URL(string: "https://shop.test/list")!) {}
    let result = try await page.callJavaScript("return " + PageRecords.script(from: from, items: items))
    return try #require(result as? [String: Any])
}

private func itemTexts(_ r: [String: Any]) -> [[String]] {
    (r["items"] as? [[String: Any]] ?? []).map { $0["text"] as? [String] ?? [] }
}

private let chrome = """
<nav><a href="/a">Home</a><a href="/b">Jobs</a><a href="/c">Companies</a><a href="/d">About us</a></nav>
<footer><ul><li><a href="/1">Privacy policy</a></li><li><a href="/2">Terms of use</a></li><li><a href="/3">Contact support</a></li></ul></footer>
"""

private func card(_ i: Int) -> String {
    """
    <div class="card shadow"><a href="/job/\(i)"><h3>Engineer \(i)</h3></a>
    <span>Acme \(i)</span><span>$\(200 + i)k</span><span>Toronto, Canada</span></div>
    """
}

@Suite("extract: page records")
struct PageRecordsTests {
    @Test @MainActor func findsCardsAndIgnoresChrome() async throws {
        let r = try await records(chrome + "<main><div class='list'>" + (1...5).map(card).joined() + "</div></main>")
        let texts = itemTexts(r)
        #expect(texts.count == 5)
        #expect(texts.first == ["Engineer 1", "Acme 1", "$201k", "Toronto, Canada"])
        let links = (r["items"] as? [[String: Any]])?.first?["links"] as? [[String: String]]
        #expect(links?.first?["url"] == "https://shop.test/job/1")
        #expect((r["itemSelector"] as? String)?.contains("div.card.shadow") == true)
    }

    @Test @MainActor func poolsCardsSplitAcrossSections() async throws {
        let sections = (0..<3).map { s in
            "<section class='row'><h2>Group \(s)</h2>" + [card(s * 2), card(s * 2 + 1)].joined() + "</section>"
        }.joined()
        let r = try await records("<main>" + sections + "</main>")
        #expect(itemTexts(r).count == 6)
    }

    @Test @MainActor func labelValueRowsInsideCardsDoNotWin() async throws {
        let cards = (1...4).map { i in
            "<div class='job'><h3>Role \(i)</h3>" + ["Team", "Level", "Place", "Pay"].map {
                "<div class='kv'><b>\($0)</b><span>value \(i)</span></div>"
            }.joined() + "</div>"
        }.joined()
        let r = try await records("<main>" + cards + "</main>")
        #expect(itemTexts(r).count == 4)
        #expect(itemTexts(r).first?.first == "Role 1")
    }

    @Test @MainActor func tableRowsAreKeyedByHeader() async throws {
        let rows = (1...3).map { "<tr><td>Item \($0)</td><td>\($0 * 10)</td><td>In stock</td></tr>" }.joined()
        let r = try await records("<table><thead><tr><th>Name</th><th>Price</th><th>Status</th></tr></thead><tbody>\(rows)</tbody></table>")
        let first = (r["items"] as? [[String: Any]])?.first?["fields"] as? [String: String]
        #expect(first == ["Name": "Item 1", "Price": "10", "Status": "In stock"])
    }

    @Test @MainActor func textFlowsThroughInlineMarkupButNotAcrossStyledSpans() async throws {
        let result = """
        <div class="r"><a href="/o/r"><span>owner/</span><em>browser</em></a>
        <p>A list of <em>headless</em> <em>web</em> browsers (<span>site.com</span>)</p><div>by <a href="/u">alice</a> 2h ago</div>
        <div><span>Rust</span><span>1.2k</span><br>line two</div></div>
        """
        let r = try await records(String(repeating: result, count: 3))
        #expect(itemTexts(r).first == [
            "owner/browser", "A list of headless web browsers (site.com)", "by alice 2h ago", "Rust", "1.2k", "line two",
        ])
    }

    @Test @MainActor func twoPiecesWithALinkIsARecord() async throws {
        let rows = (1...4).map { "<tr class='story'><td>\($0).</td><td><a href='/s/\($0)'>Story \($0)</a> (<span>site.com</span>)</td></tr>" }
        let r = try await records("<table>" + rows.joined() + "</table>")
        #expect(itemTexts(r).first == ["1.", "Story 1 (site.com)"])
        #expect(itemTexts(r).count == 4)
    }

    @Test @MainActor func headerRowsInTheBodyAndLayoutRowsAreDropped() async throws {
        let inner = "<table><tr><th>Name</th><th>Price</th><th>Status</th></tr>"
            + (1...3).map { "<tr><td>Item \($0)</td><td>\($0)</td><td>ok</td></tr>" }.joined() + "</table>"
        // An outer layout table whose row holds the real one, as on Hacker News.
        let r = try await records("<table><tr><td>\(inner)</td></tr></table>")
        #expect(itemTexts(r) == [["Item 1", "1", "ok"], ["Item 2", "2", "ok"], ["Item 3", "3", "ok"]])
    }

    @Test @MainActor func readsJSONLDGraphAndNestedMicrodata() async throws {
        let ld = #"""
        <script type="application/ld+json">{"@context":"https://schema.org","@graph":[{"@type":"JobPosting","title":"SRE","baseSalary":{"value":{"minValue":250000}}},{"@type":"WebSite","name":"X"}]}</script>
        <script type="application/ld+json">{ not json</script>
        """#
        let micro = """
        <div itemscope itemtype="https://schema.org/Product"><span itemprop="name">Lamp</span>
        <div itemprop="offers" itemscope itemtype="https://schema.org/Offer"><meta itemprop="price" content="19.99"></div>
        <a itemprop="url" href="/lamp">Lamp page</a></div>
        """
        let r = try await records(micro, head: ld)
        let structured = try #require(r["structured"] as? [[String: Any]])
        #expect(structured.map { $0["@type"] as? String } == ["JobPosting", "WebSite", "Product"])
        #expect(structured[0]["@context"] == nil)
        let product = structured[2]
        #expect(product["name"] as? String == "Lamp")
        #expect(product["url"] as? String == "https://shop.test/lamp")
        #expect((product["offers"] as? [String: Any])?["price"] as? String == "19.99")
    }

    @Test @MainActor func findsTheNextPageLink() async throws {
        let r1 = try await records("<a href='/p/1'>1</a><a href='/p/2'>Next ›</a>")
        #expect(r1["next"] as? String == "https://shop.test/p/2")
        let r2 = try await records("<a href='/p/9'>Next steps for your career</a>")
        #expect(r2["next"] is NSNull || r2["next"] == nil)
    }

    @Test @MainActor func itemsAndFromOverrideDetection() async throws {
        let body = "<ul id='a'><li>one</li><li>two</li></ul><div id='b'>" + (1...3).map(card).joined() + "</div>"
        let explicit = try await records(body, items: "#a li")
        #expect(itemTexts(explicit) == [["one"], ["two"]])
        let scoped = try await records(chrome + body, from: "#b")
        #expect(itemTexts(scoped).count == 3)
    }

    @Test func modelInputIsOneLinePerRecord() {
        let input = PageRecords.modelInput([
            "structured": [["@type": "JobPosting", "title": "SRE"]],
            "items": [["text": ["Engineer", "Acme"], "links": [["text": "Engineer", "url": "https://x.test/1"]]]],
        ])
        #expect(input == """
            structured data: {"@type":"JobPosting","title":"SRE"}
            - Engineer | Acme | links: Engineer <https://x.test/1>
            """)
    }
}

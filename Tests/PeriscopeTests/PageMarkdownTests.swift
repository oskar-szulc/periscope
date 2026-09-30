import Foundation
import Testing
import WebKit

@testable import Periscope

/// `text` reads the rendered DOM, so it is tested in a real WebKit page.
@MainActor
private func markdown(_ body: String, selector: String? = nil, links: Bool = true, images: Bool = false) async throws -> String? {
    let page = WebPage()
    for try await _ in page.load(html: "<html><body>\(body)</body></html>", baseURL: URL(string: "https://x.test/dir/")!) {}
    _ = try await page.callJavaScript(ElementResolver.installScript)
    return try await page.callJavaScript("return " + PageMarkdown.script(selector: selector, links: links, images: images))
        as? String
}

@Suite("text: rendered markdown")
struct PageMarkdownTests {
    @Test @MainActor func blocksHeadingsAndInlineMarkup() async throws {
        #expect(
            try await markdown("<h1>Title</h1><p>Hello <b>bold</b> and <i>it</i></p><p>World</p>")
                == "# Title\n\nHello **bold** and *it*\n\nWorld")
        // A div laid out as a block is its own paragraph; inline spans are not.
        #expect(try await markdown("<div>one <span>two</span></div><div>three</div>") == "one two\n\nthree")
        #expect(try await markdown("<p>Line one<br>Line two</p>") == "Line one\nLine two")
        #expect(try await markdown("<p>  Hello   \n  World  </p>") == "Hello World")
    }

    @Test @MainActor func onlyWhatIsRenderedShowsUp() async throws {
        // Empty icon-font tags and CSS-hidden text leave nothing (the regex converter printed "**").
        #expect(try await markdown("<p><i class='icon-star'></i><i class='icon-star'></i>Rated</p>") == "Rated")
        #expect(try await markdown("<p>Shown</p><p style='display:none'>Hidden</p><p hidden>Also hidden</p>") == "Shown")
        #expect(try await markdown("<nav>Menu</nav><p>Content</p><script>var x=1</script><footer>Legal</footer>") == "Content")
    }

    @Test @MainActor func linksAreAbsoluteAndOptional() async throws {
        #expect(try await markdown("<a href='page'>Read</a>") == "[Read](https://x.test/dir/page)")
        #expect(try await markdown("<a href='page'>Read</a>", links: false) == "Read")
        #expect(try await markdown("<a href='javascript:void(0)'>Menu</a>") == "Menu")
    }

    @Test @MainActor func imagesOffKeepAltText() async throws {
        #expect(try await markdown("<img src='a.jpg' alt='Photo'>") == "Photo")
        #expect(try await markdown("<a href='/p'><img src='x.jpg' alt='Story'></a>") == "[Story](https://x.test/p)")
    }

    @Test @MainActor func listsIncludingNested() async throws {
        #expect(try await markdown("<ul><li>One</li><li>Two</li></ul>") == "- One\n- Two")
        #expect(try await markdown("<ol><li>First</li><li>Second</li></ol>") == "1. First\n2. Second")
        #expect(try await markdown("<ul><li>A<ul><li>A1</li></ul></li><li>B</li></ul>") == "- A\n  - A1\n- B")
    }

    @Test @MainActor func codeTablesAndQuotes() async throws {
        #expect(try await markdown("<pre><code>let x = 1</code></pre>") == "```\nlet x = 1\n```")
        #expect(try await markdown("<p>Call <code>foo()</code></p>") == "Call `foo()`")
        let table = "<table><tr><th>Name</th><th>Age</th></tr><tr><td>Alice</td><td>30</td></tr></table>"
        #expect(try await markdown(table) == "| Name | Age |\n| --- | --- |\n| Alice | 30 |")
        #expect(try await markdown("<blockquote><p>Said</p></blockquote>") == "> Said")
        // Layout tables (a table of tables, as on Hacker News) read as blocks.
        let layout = "<table><tr><td>Site</td></tr><tr><td><table><tr><td>1.</td><td>Story</td></tr></table></td></tr></table>"
        #expect(try await markdown(layout) == "Site\n\n| 1. | Story |")
    }

    @Test @MainActor func aSelectorScopesItAndAMissOneIsNil() async throws {
        #expect(try await markdown("<main><h2 id='x'>Here</h2></main><p>not here</p>", selector: "#x") == "## Here")
        #expect(try await markdown("<p>x</p>", selector: "#nope") == nil)
    }
}

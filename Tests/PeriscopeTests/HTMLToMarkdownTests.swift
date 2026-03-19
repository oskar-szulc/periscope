import Testing
@testable import Periscope

@Suite("HTMLToMarkdown")
struct HTMLToMarkdownTests {
    let converter = HTMLToMarkdown()

    @Test func headings() {
        #expect(converter.convert("<h1>Title</h1>") == "# Title")
        #expect(converter.convert("<h2>Subtitle</h2>") == "## Subtitle")
        #expect(converter.convert("<h3>Section</h3>") == "### Section")
    }

    @Test func paragraphs() {
        #expect(converter.convert("<p>Hello</p><p>World</p>") == "Hello\n\nWorld")
    }

    @Test func links() {
        #expect(converter.convert("<a href=\"/about\">About</a>") == "[About](/about)")
    }

    @Test func images() {
        #expect(converter.convert("<img src=\"pic.jpg\" alt=\"Photo\">") == "![Photo](pic.jpg)")
    }

    @Test func bold() {
        #expect(converter.convert("<strong>bold</strong>") == "**bold**")
        #expect(converter.convert("<b>bold</b>") == "**bold**")
    }

    @Test func italic() {
        #expect(converter.convert("<em>italic</em>") == "*italic*")
        #expect(converter.convert("<i>italic</i>") == "*italic*")
    }

    @Test func unorderedList() {
        let html = "<ul><li>One</li><li>Two</li><li>Three</li></ul>"
        #expect(converter.convert(html) == "- One\n- Two\n- Three")
    }

    @Test func orderedList() {
        let html = "<ol><li>First</li><li>Second</li></ol>"
        #expect(converter.convert(html) == "1. First\n2. Second")
    }

    @Test func codeBlock() {
        let html = "<pre><code>let x = 1</code></pre>"
        #expect(converter.convert(html) == "```\nlet x = 1\n```")
    }

    @Test func inlineCode() {
        #expect(converter.convert("<code>foo()</code>") == "`foo()`")
    }

    @Test func table() {
        let html = """
        <table>
        <tr><th>Name</th><th>Age</th></tr>
        <tr><td>Alice</td><td>30</td></tr>
        </table>
        """
        let expected = "| Name | Age |\n| --- | --- |\n| Alice | 30 |"
        #expect(converter.convert(html) == expected)
    }

    @Test func stripsScripts() {
        let html = "<p>Hello</p><script>alert('xss')</script><p>World</p>"
        #expect(converter.convert(html) == "Hello\n\nWorld")
    }

    @Test func stripsNav() {
        let html = "<nav><a href='/'>Home</a></nav><p>Content</p>"
        #expect(converter.convert(html) == "Content")
    }

    @Test func collapsesWhitespace() {
        let html = "<p>Hello     World</p>"
        #expect(converter.convert(html) == "Hello World")
    }

    @Test func lineBreaks() {
        let html = "<p>Line one<br>Line two</p>"
        #expect(converter.convert(html) == "Line one\nLine two")
    }
}

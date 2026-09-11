import Testing
import Foundation
@testable import Periscope

@Suite("TextFormatter")
struct TextFormatterTests {
    let formatter = TextFormatter()

    @Test func navigateOutput() {
        let result = CommandResult.navigate(
            title: "Example", url: "https://example.com/", status: 200, textChars: 1234)
        let output = formatter.format(result)
        #expect(output == "Navigated to: Example\nURL: https://example.com/\nStatus: 200 \u{00B7} Text: 1,234 chars")
    }

    @Test func navigateOutputWithoutStatus() {
        // A file:// or about: load has no HTTP response; say so rather than print 0.
        let result = CommandResult.navigate(
            title: nil, url: "about:blank", status: nil, textChars: 0)
        let output = formatter.format(result)
        #expect(output == "Navigated to: (untitled)\nURL: about:blank\nStatus: - \u{00B7} Text: 0 chars")
    }

    @Test func errorOutput() {
        let result = CommandResult.error("Element not found: #foo")
        let output = formatter.format(result)
        #expect(output == "Error: Element not found: #foo")
    }

    @Test func extractOutput() {
        let result = CommandResult.extract(content: "# Hello\n\nWorld")
        let output = formatter.format(result)
        #expect(output == "# Hello\n\nWorld")
    }

    @Test func linksOutput() {
        let result = CommandResult.links([
            LinkItem(text: "About", url: "/about"),
            LinkItem(text: "Blog", url: "https://blog.example.com"),
        ])
        let output = formatter.format(result)
        #expect(output == "- [About](/about)\n- [Blog](https://blog.example.com)")
    }
}

@Suite("JSONFormatter")
struct JSONFormatterTests {
    let formatter = JSONFormatter()

    @Test func navigateOutput() throws {
        let result = CommandResult.navigate(
            title: "Example", url: "https://example.com/", status: 404, textChars: 9)
        let output = formatter.format(result)
        let json = try JSONSerialization.jsonObject(with: Data(output.utf8)) as! [String: Any]
        #expect(json["ok"] as? Bool == true)
        #expect(json["title"] as? String == "Example")
        #expect(json["url"] as? String == "https://example.com/")
        #expect(json["status"] as? Int == 404)
        #expect(json["textChars"] as? Int == 9)
    }

    @Test func errorOutput() throws {
        let result = CommandResult.error("Element not found: #foo")
        let output = formatter.format(result)
        let json = try JSONSerialization.jsonObject(with: Data(output.utf8)) as! [String: Any]
        #expect(json["ok"] as? Bool == false)
        #expect(json["error"] as? String == "Element not found: #foo")
    }
}

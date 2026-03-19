import Testing
import Foundation
@testable import Periscope

@Suite("TextFormatter")
struct TextFormatterTests {
    let formatter = TextFormatter()

    @Test func navigateOutput() {
        let result = CommandResult.navigate(title: "Example", url: "https://example.com/")
        let output = formatter.format(result)
        #expect(output == "Navigated to: Example\nURL: https://example.com/")
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
        let result = CommandResult.navigate(title: "Example", url: "https://example.com/")
        let output = formatter.format(result)
        let json = try JSONSerialization.jsonObject(with: Data(output.utf8)) as! [String: Any]
        #expect(json["ok"] as? Bool == true)
        #expect(json["title"] as? String == "Example")
        #expect(json["url"] as? String == "https://example.com/")
    }

    @Test func errorOutput() throws {
        let result = CommandResult.error("Element not found: #foo")
        let output = formatter.format(result)
        let json = try JSONSerialization.jsonObject(with: Data(output.utf8)) as! [String: Any]
        #expect(json["ok"] as? Bool == false)
        #expect(json["error"] as? String == "Element not found: #foo")
    }
}

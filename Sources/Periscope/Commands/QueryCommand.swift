import ArgumentParser
import Foundation
import FoundationModels

@Generable(description: "A web page element matching the user's description")
struct FoundElement {
    @Guide(description: "CSS selector for the element")
    var selector: String
    @Guide(description: "Brief description of what the element is")
    var description: String
    @Guide(description: "Element type: link, button, input, select, form, heading, or other")
    var elementType: String
    @Guide(description: "Confidence: high, medium, or low")
    var confidence: String
}

/// `query` answers a question about the page; `find` resolves a description to a
/// selector. They were one command with a `--find` flag, which made the return
/// type depend on a flag -- prose one way, a selector the other.
struct Find: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find an interactive element by description, returning a CSS selector")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Description of the element, e.g. \"the sign in button\"")
    var description: String

    func run() throws {
        Query.execute(globals: globals, prompt: description, findElement: true)
    }
}

struct Query: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Ask a natural language question about the current page")

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Question about the page")
    var question: String

    func run() throws {
        Self.execute(globals: globals, prompt: question, findElement: false)
    }

    static func execute(globals: GlobalOptions, prompt: String, findElement: Bool) {
        CommandRunner.run(globals: globals) { engine in
            // Extract page summary
            guard
                let json = try await engine.runJavaScript(
                    PageSummarizer.extractScript) as? String
            else {
                throw PeriscopeError.javaScriptError(reason: "Failed to extract page summary")
            }

            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw PeriscopeError.argumentError(
                    reason: "Apple Intelligence is not available on this device")
            }

            if findElement {
                return try await Self.findElement(json: json, question: prompt, asJson: globals.json)
            } else {
                return try await Self.answerQuestion(json: json, question: prompt)
            }
        }
    }

    /// Answer a freeform question about the page.
    private static func answerQuestion(json: String, question: String) async throws -> CommandResult {
        let session = LanguageModelSession(
            instructions: """
                You answer questions about web pages. You receive a JSON summary of the \
                page containing its title, URL, text content, and interactive elements. \
                Answer concisely based only on the page content. If the answer isn't in \
                the content, say so.
                """)

        let response = try await session.respond(
            to: """
                Page data:
                \(json)

                Question: \(question)
                """)
        return .extract(content: response.content)
    }

    /// Find an interactive element matching a natural language description.
    private static func findElement(json: String, question: String, asJson: Bool) async throws -> CommandResult {
        let session = LanguageModelSession(
            instructions: """
                You find interactive elements on web pages. You receive a JSON summary \
                containing the page's elements with their tags, attributes, text, and \
                selectors. Find the element that best matches the user's description. \
                Use the selector from the elements list when possible. Prefer IDs, then \
                name attributes, then aria-labels for selectors.
                """)

        let response = try await session.respond(
            to: """
                Page elements:
                \(json)

                Find: \(question)
                """, generating: FoundElement.self)

        let el = response.content
        if asJson {
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "ok": true,
                    "selector": el.selector,
                    "description": el.description,
                    "type": el.elementType,
                    "confidence": el.confidence,
                ] as [String: Any], options: [.sortedKeys])
            return .plain(String(data: data, encoding: .utf8) ?? "{}")
        }
        return .plain("\(el.selector)  (\(el.elementType): \(el.description)) [\(el.confidence)]")
    }
}

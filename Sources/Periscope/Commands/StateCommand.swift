import ArgumentParser
import Foundation

/// Answers an agent's actual question -- "where am I and what can I do here" --
/// in one call.
///
/// Orienting on a page previously took three commands (`url`, `text`,
/// `elements`), which for an agent means three round trips and three tool
/// results in context. The page work is ~2ms; the round trips are the cost.
struct State: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print URL, title, content and every actionable element in one call")

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .long, help: "Omit page text, list only actionable elements")
    var actionsOnly: Bool = false

    @Option(name: .long, help: "Truncate page text to this many characters")
    var textLimit: Int?

    func run() throws {
        let actionsOnly = actionsOnly
        let textLimit = textLimit

        CommandRunner.run(globals: globals) { engine in
            guard let json = try await engine.runJavaScript(
                PageSummarizer.extractScript) as? String,
                let data = json.data(using: .utf8) else {
                throw PeriscopeError.javaScriptError(reason: "Failed to extract page state")
            }

            var state = try JSONDecoder().decode(PageStateData.self, from: data)

            if actionsOnly {
                state.text = ""
                state.truncated = false
            } else if let limit = textLimit, state.text.count > limit {
                state.text = String(state.text.prefix(limit))
                state.truncated = true
            }
            return .state(state)
        }
    }
}

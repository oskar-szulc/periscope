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

    @Option(name: .long, help: "Keep only actions whose selector, label, text or href matches this regex")
    var match: String?

    @Flag(name: .long, help: "List every action instead of the first \(StateFilter.defaultLimit)")
    var all: Bool = false

    @Option(name: .long, help: "Write the full output to this file and print a one-line summary")
    var out: String?

    func run() throws {
        let actionsOnly = actionsOnly
        let textLimit = textLimit
        let match = match
        let limit: Int? = all ? nil : StateFilter.defaultLimit
        let outPath = out.map(CommandRunner.resolvePath)
        let json = globals.json

        CommandRunner.run(globals: globals) { engine in
            guard let raw = try await engine.runJavaScript(
                PageSummarizer.extractScript) as? String,
                let data = raw.data(using: .utf8) else {
                throw PeriscopeError.javaScriptError(reason: "Failed to extract page state")
            }

            var state = try JSONDecoder().decode(PageStateData.self, from: data)
            state.blocked = try await engine.detectBlock()?.rawValue

            if actionsOnly {
                state.text = ""
                state.truncated = false
            } else if let limit = textLimit, state.text.count > limit {
                state.text = String(state.text.prefix(limit))
                state.truncated = true
            }
            // A file gets everything; the cap exists to protect the transcript.
            state = try StateFilter.apply(state, match: match, limit: outPath == nil ? limit : nil)

            if let outPath {
                let rendered = makeFormatter(json: json).format(.state(state))
                do {
                    try rendered.write(toFile: outPath, atomically: true, encoding: .utf8)
                } catch {
                    throw PeriscopeError.argumentError(reason: "Cannot write \(outPath): \((error as NSError).localizedDescription)")
                }
                return .plain("State written to \(outPath) (\(state.elements.count) actions, \(rendered.count) chars)")
            }
            return .state(state)
        }
    }
}

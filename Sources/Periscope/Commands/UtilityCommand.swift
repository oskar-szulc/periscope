import ArgumentParser
import Foundation

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for a condition")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Strategy: load, fetchquiet, fetchquiet:<maxMs>, selector:<target>, time:<ms>") var strategy: String
    func run() throws {
        guard let parsed = WaitStrategy.parse(strategy) else {
            throw PeriscopeError.argumentError(reason: "Unknown wait strategy: \(strategy)")
        }
        CommandRunner.run(globals: globals) { engine in
            try await engine.waitFor(parsed)
            return .plain("Wait complete: \(strategy)")
        }
    }
}

struct Elements: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List matching elements")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: ArgumentHelp(stringLiteral: targetHelp)) var selector: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            guard let results = try await engine.runJavaScript(
                ElementResolver.elementsScript(selector: selector)) as? [[String: Any]] else {
                return .elements([])
            }
            return .elements(results.map {
                ElementItem(index: $0["index"] as? Int ?? 0, tag: $0["tag"] as? String ?? "",
                    id: $0["id"] as? String, classes: $0["classes"] as? [String] ?? [],
                    text: $0["text"] as? String ?? "")
            })
        }
    }
}

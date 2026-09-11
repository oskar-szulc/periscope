import ArgumentParser
import Foundation

/// What the page fetched, and what it said while doing it. Both come from
/// monitors injected at document start, so they cover the page's own scripts
/// from the first byte, not just what happened after periscope looked.
struct Requests: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List fetch/XHR requests the current page has made, with status codes")
    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Keep only requests whose URL matches this regex")
    var match: String?
    @Option(name: .long, help: "Wait up to this many ms for in-flight requests to resolve first (0 to skip)")
    var settle: Int = 2000
    @Flag(name: .long, help: "Show only requests that failed or are still pending")
    var unresolved: Bool = false

    func run() throws {
        let match = match
        let settle = settle
        let unresolved = unresolved
        CommandRunner.run(globals: globals) { engine in
            try await engine.settleRequests(maxMs: settle)
            var items = try await engine.recordedRequests()
            if let match {
                guard let regex = try? NSRegularExpression(pattern: match) else {
                    throw PeriscopeError.argumentError(reason: "Invalid --match regex: \(match)")
                }
                items = items.filter {
                    regex.firstMatch(in: $0.url, range: NSRange($0.url.startIndex..., in: $0.url)) != nil
                }
            }
            if unresolved { items = items.filter { $0.status == nil } }
            return .requests(items)
        }
    }
}

struct Console: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print console output and uncaught errors from the current page")
    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Only this level: error, warn, log, info, debug")
    var level: String?

    func run() throws {
        let level = level
        CommandRunner.run(globals: globals) { engine in
            var items = try await engine.consoleMessages()
            if let level { items = items.filter { $0.level == level } }
            return .console(items)
        }
    }
}

import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Session name")
    var session: String = "default"

    @Flag(name: .long, help: "Disable session persistence")
    var noSession: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Timeout in seconds (0: no limit)")
    var timeout: Int = 30

    @Option(name: .long, help: "Viewport size (WxH)")
    var viewport: String = "1920x1080"

    @Option(name: .long, help: "Override user agent")
    var userAgent: String?

    @Option(name: .long, help: "Wait strategy: none, load, fetchquiet, fetchquiet:<maxMs>, selector:<css>, time:<ms>")
    var wait: String?

    @Flag(name: .long, help: "Print navigation events to stderr")
    var verbose: Bool = false

    /// Ambiguity is an error by default: acting on the first of several matches
    /// produced wrong results with no signal. This flag opts back in.
    @Flag(name: .long, help: "When a target matches several elements, act on the first instead of failing")
    var first: Bool = false

    /// Accepted for scripts written against the old default; it is now a no-op.
    @Flag(name: .customLong("strict"), help: .hidden)
    var legacyStrict: Bool = false

    @Flag(name: .long, help: "Run in-process instead of via the session daemon")
    var noDaemon: Bool = false

    var strict: Bool { !first }

    var viewportSize: (width: Int, height: Int) { parseViewport(viewport) }

    /// A misspelt `--wait` used to fall back silently; now it is an error, since
    /// "waited the wrong way" is indistinguishable from "page is empty".
    func waitStrategy(default fallback: WaitStrategy) throws -> WaitStrategy {
        guard let wait else { return fallback }
        guard let parsed = WaitStrategy.parse(wait) else {
            throw PeriscopeError.argumentError(reason: "Unknown wait strategy: \(wait)")
        }
        return parsed
    }
}

/// Shared by `GlobalOptions` and its wire payload so the default cannot drift.
func parseViewport(_ value: String) -> (width: Int, height: Int) {
    let parts = value.split(separator: "x").compactMap { Int($0) }
    guard parts.count == 2 else { return (1920, 1080) }
    return (parts[0], parts[1])
}

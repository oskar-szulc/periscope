import ArgumentParser

struct GlobalOptions: ParsableArguments {
    @Option(name: .long, help: "Session name")
    var session: String = "default"

    @Flag(name: .long, help: "Disable session persistence")
    var noSession: Bool = false

    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false

    @Option(name: .long, help: "Timeout in seconds")
    var timeout: Int = 30

    @Option(name: .long, help: "Viewport size (WxH)")
    var viewport: String = "1920x1080"

    @Option(name: .long, help: "Override user agent")
    var userAgent: String?

    @Option(name: .long, help: "Wait strategy: load, fetchquiet, selector:<css>, time:<ms>")
    var wait: String?

    @Flag(name: .long, help: "Print navigation events to stderr")
    var verbose: Bool = false

    @Flag(name: .long, help: "Error if selector matches multiple elements")
    var strict: Bool = false

    @Flag(name: .long, help: "Run in-process instead of via the session daemon")
    var noDaemon: Bool = false

    var viewportSize: (width: Int, height: Int) {
        let parts = viewport.split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2 else { return (1920, 1080) }
        return (parts[0], parts[1])
    }
}

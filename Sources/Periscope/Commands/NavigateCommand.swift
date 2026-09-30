import ArgumentParser
import Foundation

/// What every navigation command does after the load event: settle, refuse
/// challenge pages, and report enough that an empty result is visible.
///
/// `--wait` used to be honoured by `click` alone, so `navigate --wait time:4000`
/// silently did nothing and an SPA job board read as nine bytes of asterisks.
enum NavigationReport {
    /// The shared body of every navigation command: parse `--wait`, run the
    /// navigation, then report. Parsing `--wait` inside the runner means a typo
    /// exits like any other argument error rather than being ignored.
    static func run(
        globals: GlobalOptions,
        challengeSeconds: Int = 0,
        navigate: @escaping @MainActor @Sendable (BrowserEngine) async throws -> String
    ) {
        CommandRunner.run(globals: globals) { engine in
            let wait = try globals.waitStrategy(default: .navigateDefault)
            let url = try await navigate(engine)
            return try await make(engine: engine, wait: wait, fallbackURL: url, challengeSeconds: challengeSeconds)
        }
    }

    @MainActor
    static func make(engine: BrowserEngine, wait: WaitStrategy, fallbackURL: String,
                     challengeSeconds: Int = 0) async throws -> CommandResult {
        try await engine.waitFor(wait)

        // One look at the settled page: title, text size and challenge check.
        var page = try await engine.observePage()
        // A managed challenge (Cloudflare) often clears itself after a few
        // seconds of JS and reloads into the real page; give it that time
        // before calling the page blocked.
        let deadline = ContinuousClock.now + .seconds(challengeSeconds)
        while page.blocked != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(500))
            // Mid-reload the page may refuse JS: keep the last look.
            page = (try? await engine.observePage()) ?? page
            if page.blocked == nil {
                try await engine.waitFor(wait)
                page = try await engine.observePage()
            }
        }
        let url = engine.currentURL ?? fallbackURL
        if let kind = page.blocked {
            throw PeriscopeError.blocked(kind: kind, url: url)
        }
        return .navigate(title: page.title, url: url, status: engine.lastStatusCode, textChars: page.textChars, htmlChars: page.htmlChars)
    }
}

struct Navigate: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Navigate to a URL")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "URL to navigate to") var url: String
    @Option(name: .long, help: "Seconds to let a bot challenge clear itself before failing as blocked (needs --timeout above it)")
    var waitChallenge: Int = 0

    func run() throws {
        guard let parsedURL = URL(string: url) else {
            throw PeriscopeError.argumentError(reason: "Invalid URL: \(url)")
        }
        if waitChallenge > 0 && globals.timeout > 0 && waitChallenge + 10 > globals.timeout {
            throw PeriscopeError.argumentError(
                reason: "--wait-challenge \(waitChallenge) needs --timeout of at least \(waitChallenge + 10) to leave room for the load")
        }
        NavigationReport.run(globals: globals, challengeSeconds: waitChallenge) { try await $0.navigate(to: parsedURL) }
    }
}

struct Back: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Go back in history")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        NavigationReport.run(globals: globals) { try await $0.goBack() }
    }
}

struct Forward: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Go forward in history")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        NavigationReport.run(globals: globals) { try await $0.goForward() }
    }
}

struct Reload: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Reload current page")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        NavigationReport.run(globals: globals) { try await $0.reload() }
    }
}

struct CurrentURL: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "url", abstract: "Print current URL")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            .plain(engine.currentURL ?? "(no page loaded)")
        }
    }
}

struct History: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print back/forward list")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let items = try await engine.getHistory()
            return .history(items: items)
        }
    }
}

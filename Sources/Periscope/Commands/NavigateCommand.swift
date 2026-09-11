import ArgumentParser
import Foundation

/// What every navigation command does after the load event: settle, refuse
/// challenge pages, and report enough that an empty result is visible.
///
/// `--wait` used to be honoured by `click` alone, so `navigate --wait time:4000`
/// silently did nothing and an SPA job board read as nine bytes of asterisks.
enum NavigationReport {
    @MainActor
    static func make(engine: BrowserEngine, wait: WaitStrategy, fallbackURL: String) async throws -> CommandResult {
        try await engine.waitFor(wait)

        let url = engine.currentURL ?? fallbackURL
        if let kind = try await engine.detectBlock() {
            throw PeriscopeError.blocked(kind: kind, url: url)
        }
        // Title is re-read after the wait: an SPA sets it from JavaScript.
        let title = await engine.resolveTitle()
        let chars = await engine.measureTextChars()
        return .navigate(title: title, url: url, status: engine.lastStatusCode, textChars: chars)
    }
}

struct Navigate: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Navigate to a URL")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "URL to navigate to") var url: String

    func run() throws {
        guard let parsedURL = URL(string: url) else {
            throw PeriscopeError.argumentError(reason: "Invalid URL: \(url)")
        }
        let globals = globals
        CommandRunner.run(globals: globals) { engine in
            // Parsed before the load so a typo fails fast, and inside the runner
            // so it exits 4 like every other argument error.
            let wait = try globals.waitStrategy(default: .navigateDefault)
            let (_, finalURL) = try await engine.navigate(to: parsedURL)
            return try await NavigationReport.make(engine: engine, wait: wait, fallbackURL: finalURL)
        }
    }
}

struct Back: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Go back in history")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        let globals = globals
        CommandRunner.run(globals: globals) { engine in
            // Parsed before the load so a typo fails fast, and inside the runner
            // so it exits 4 like every other argument error.
            let wait = try globals.waitStrategy(default: .navigateDefault)
            let (_, url) = try await engine.goBack()
            return try await NavigationReport.make(engine: engine, wait: wait, fallbackURL: url)
        }
    }
}

struct Forward: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Go forward in history")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        let globals = globals
        CommandRunner.run(globals: globals) { engine in
            // Parsed before the load so a typo fails fast, and inside the runner
            // so it exits 4 like every other argument error.
            let wait = try globals.waitStrategy(default: .navigateDefault)
            let (_, url) = try await engine.goForward()
            return try await NavigationReport.make(engine: engine, wait: wait, fallbackURL: url)
        }
    }
}

struct Reload: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Reload current page")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        let globals = globals
        CommandRunner.run(globals: globals) { engine in
            // Parsed before the load so a typo fails fast, and inside the runner
            // so it exits 4 like every other argument error.
            let wait = try globals.waitStrategy(default: .navigateDefault)
            let (_, url) = try await engine.reload()
            return try await NavigationReport.make(engine: engine, wait: wait, fallbackURL: url)
        }
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

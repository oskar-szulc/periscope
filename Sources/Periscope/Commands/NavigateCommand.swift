import ArgumentParser
import Foundation

struct Navigate: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Navigate to a URL")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "URL to navigate to") var url: String

    func run() throws {
        guard let parsedURL = URL(string: url) else {
            throw PeriscopeError.argumentError(reason: "Invalid URL: \(url)")
        }
        CommandRunner.run(globals: globals) { engine in
            let (title, finalURL) = try await engine.navigate(to: parsedURL)
            return .navigate(title: title, url: finalURL)
        }
    }
}

struct Back: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Go back in history")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let (title, url) = try await engine.goBack()
            return .navigate(title: title, url: url)
        }
    }
}

struct Forward: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Go forward in history")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let (title, url) = try await engine.goForward()
            return .navigate(title: title, url: url)
        }
    }
}

struct Reload: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Reload current page")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let (title, url) = try await engine.reload()
            return .navigate(title: title, url: url)
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

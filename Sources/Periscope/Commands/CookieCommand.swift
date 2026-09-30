import ArgumentParser
import Foundation

/// Cookies live in WebKit's jar for the session's data store, not in
/// `document.cookie`. Reading the jar shows every host and HttpOnly cookies;
/// writing it needs no page to be loaded first.
struct Cookie: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage cookies",
        subcommands: [CookieListCmd.self, CookieSetCmd.self, CookieDeleteCmd.self])
}

struct CookieSetCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set a cookie")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Cookie name") var name: String
    @Argument(help: "Cookie value") var value: String
    @Option(name: .long, help: "Domain (default: current page's host)") var domain: String?
    @Option(name: .long, help: "Path") var path: String = "/"
    @Flag(name: .long, help: "Secure") var secure: Bool = false
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            guard let host = domain ?? engine.currentURL.flatMap({ URL(string: $0)?.host }) else {
                throw PeriscopeError.argumentError(reason: "No page loaded; pass --domain")
            }
            guard
                let cookie = PersistedCookie(
                    name: name, value: value, domain: host, path: path,
                    expires: nil, secure: secure, httpOnly: false
                ).httpCookie
            else {
                throw PeriscopeError.argumentError(reason: "Invalid cookie")
            }
            await engine.setCookies([cookie])
            return .plain("Cookie set: \(name) for \(host)")
        }
    }
}

struct CookieDeleteCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a cookie")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Cookie name") var name: String
    @Option(name: .long, help: "Only on this domain") var domain: String?
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let victims = await engine.allCookies().filter {
                $0.name == name && (domain == nil || $0.domain == domain)
            }
            for cookie in victims { await engine.deleteCookie(cookie) }
            return .plain("Cookie deleted: \(name) (\(victims.count) removed)")
        }
    }
}

struct CookieListCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List every cookie in the session's jar")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let items = await engine.allCookies()
                .sorted { ($0.domain, $0.name) < ($1.domain, $1.name) }
                .map { CookieItem(name: $0.name, value: $0.value, domain: $0.domain) }
            return .cookies(items)
        }
    }
}

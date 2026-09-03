import ArgumentParser
import Foundation

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
    @Option(name: .long, help: "Domain") var domain: String?
    @Option(name: .long, help: "Path") var path: String = "/"
    @Flag(name: .long, help: "Secure") var secure: Bool = false
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            var parts = ["\(name)=\(value)", "path=\(path)"]
            if let domain { parts.append("domain=\(domain)") }
            if secure { parts.append("secure") }
            let cookieStr = parts.joined(separator: "; ")
            try await engine.runJavaScriptVoid("document.cookie = \(ElementResolver.jsString(cookieStr))")
            return .plain("Cookie set: \(name)")
        }
    }
}

struct CookieDeleteCmd: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a cookie")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Cookie name") var name: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let cookieStr = "\(name)=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/"
            try await engine.runJavaScriptVoid("document.cookie = \(ElementResolver.jsString(cookieStr))")
            return .plain("Cookie deleted: \(name)")
        }
    }
}

struct CookieListCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List cookies for the current page")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let str = try await engine.runJavaScript("document.cookie") as? String ?? ""
            guard !str.isEmpty else { return .cookies([]) }
            let host = engine.currentURL.flatMap { URL(string: $0)?.host } ?? ""
            let items = parseDocumentCookie(str).map {
                CookieItem(name: $0.name, value: $0.value, domain: host)
            }
            return .cookies(items)
        }
    }
}

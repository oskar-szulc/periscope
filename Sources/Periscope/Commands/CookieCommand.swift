import ArgumentParser
import Foundation

struct Cookie: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage cookies",
        subcommands: [CookieSetCmd.self, CookieDeleteCmd.self])
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
            _ = try await engine.runJavaScript("document.cookie = \(ElementResolver.jsString(cookieStr))")
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
            _ = try await engine.runJavaScript("document.cookie = \(ElementResolver.jsString(cookieStr))")
            return .plain("Cookie deleted: \(name)")
        }
    }
}

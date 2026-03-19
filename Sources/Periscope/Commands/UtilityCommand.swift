import ArgumentParser
import Foundation

struct Wait: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Wait for a condition")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Strategy: load, fetchquiet, selector:<css>, time:<ms>") var strategy: String
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
    @Argument(help: "CSS selector") var selector: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let js = """
            Array.from(document.querySelectorAll(\(ElementResolver.jsString(selector)))).map(function(el, i) {
                return { index: i + 1, tag: el.tagName.toLowerCase(), id: el.id || null, classes: Array.from(el.classList), text: el.textContent.trim().substring(0, 80) };
            })
            """
            guard let results = try await engine.runJavaScript(js) as? [[String: Any]] else {
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

struct Cookies: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List cookies for current page")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let str = try await engine.runJavaScript("document.cookie") as? String ?? ""
            guard !str.isEmpty else { return .cookies([]) }
            let items = str.split(separator: ";").map { pair in
                let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                let host = engine.currentURL.flatMap { URL(string: $0)?.host } ?? ""
                return CookieItem(name: String(parts[0]), value: parts.count > 1 ? String(parts[1]) : "", domain: host)
            }
            return .cookies(items)
        }
    }
}

import ArgumentParser
import Foundation

struct Extract: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Extract text content as markdown")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector (optional)") var selector: String?
    @Flag(name: .long, help: "Raw text, no markdown") var raw: Bool = false

    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            let content = try await engine.extractText(selector: selector, raw: raw)
            return .extract(content: content)
        }
    }
}

struct HTML: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "html", abstract: "Extract raw HTML")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector (optional)") var selector: String?

    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            .html(content: try await engine.extractHTML(selector: selector))
        }
    }
}

struct Attr: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Get an element attribute value")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector") var selector: String
    @Argument(help: "Attribute name") var attribute: String

    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.resolveElement(selector: selector, strict: globals.strict)
            return .plain(try await engine.extractAttribute(selector: selector, attribute: attribute))
        }
    }
}

struct Links: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List all links on the page")
    @OptionGroup var globals: GlobalOptions

    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            .links(try await engine.extractLinks())
        }
    }
}

struct Table: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "table", abstract: "Extract a table as markdown")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector for the table") var selector: String

    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            .extract(content: try await engine.extractTable(selector: selector))
        }
    }
}

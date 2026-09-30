import ArgumentParser
import Foundation

struct Extract: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Extract text content as markdown")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector (optional)") var selector: String?
    @Flag(name: .long, help: "Plain rendered text, no markdown") var raw: Bool = false
    @Flag(name: .long, help: "Include image markup (off by default; alt text is kept)") var images: Bool = false
    @Flag(name: .long, help: "Drop link targets, keeping the link text (use links or state for URLs)") var noLinks: Bool = false

    func run() throws {
        let (links, images) = (!noLinks, images)
        CommandRunner.run(globals: globals) { engine in
            let content = try await engine.extractText(selector: selector, raw: raw, links: links, images: images)
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
    @Option(name: .long, help: "Keep only links whose URL matches this regex")
    var match: String?

    func run() throws {
        let match = match
        CommandRunner.run(globals: globals) { engine in
            var links = try await engine.extractLinks()
            if let match { links = try LinkFilter.apply(pattern: match, to: links) }
            return .links(links)
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

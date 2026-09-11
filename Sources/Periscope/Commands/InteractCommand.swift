import ArgumentParser

/// Shared tail of every interaction: settle, then report a navigation if the
/// action caused one. `click` on a link used to print "Clicked" and nothing
/// else; the agent had to spend another call to learn where it landed.
enum InteractionReport {
    @MainActor
    static func after(
        engine: BrowserEngine, globals: GlobalOptions, urlBefore: String?, otherwise: String
    ) async throws -> CommandResult {
        let wait = try globals.waitStrategy(default: .fetchquiet(maxMs: nil))
        try await engine.waitFor(wait)
        if let now = engine.currentURL, now != urlBefore {
            return try await NavigationReport.make(engine: engine, wait: WaitStrategy.none, fallbackURL: now)
        }
        return .plain(otherwise)
    }
}

let targetHelp = "Target: CSS selector, or text:<visible text>, label:<label>, placeholder:<text>, role:<role> [name=<text>]"

struct Click: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Click an element")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: ArgumentHelp(stringLiteral: targetHelp)) var selector: String
    func run() throws {
        let globals = globals
        CommandRunner.run(globals: globals) { engine in
            let before = engine.currentURL
            try await engine.click(selector: selector, strict: globals.strict)
            return try await InteractionReport.after(
                engine: engine, globals: globals, urlBefore: before, otherwise: "Clicked: \(selector)")
        }
    }
}

struct Fill: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Fill a form field")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: ArgumentHelp(stringLiteral: targetHelp)) var selector: String
    @Argument(help: "Value to set") var value: String
    @Flag(name: .long, help: "Press Enter afterwards, submitting the field's form")
    var submit: Bool = false
    func run() throws {
        let globals = globals
        let submit = submit
        CommandRunner.run(globals: globals) { engine in
            let before = engine.currentURL
            try await engine.fill(selector: selector, value: value, strict: globals.strict)
            guard submit else { return .plain("Filled \(selector) with value") }
            try await engine.pressEnter(selector: selector)
            return try await InteractionReport.after(
                engine: engine, globals: globals, urlBefore: before,
                otherwise: "Filled \(selector) and submitted")
        }
    }
}

struct SelectOption: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "select", abstract: "Choose a <select> option")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: ArgumentHelp(stringLiteral: targetHelp)) var selector: String
    @Argument(help: "Option value") var value: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.selectOption(selector: selector, value: value, strict: globals.strict)
            return .plain("Selected \(value) in \(selector)")
        }
    }
}

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check a checkbox")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: ArgumentHelp(stringLiteral: targetHelp)) var selector: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.setChecked(selector: selector, checked: true, strict: globals.strict)
            return .plain("Checked: \(selector)")
        }
    }
}

struct Uncheck: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Uncheck a checkbox")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: ArgumentHelp(stringLiteral: targetHelp)) var selector: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.setChecked(selector: selector, checked: false, strict: globals.strict)
            return .plain("Unchecked: \(selector)")
        }
    }
}

struct Submit: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Submit a form")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "Form, or a field inside it (optional; defaults to the first form)") var selector: String?
    func run() throws {
        let globals = globals
        CommandRunner.run(globals: globals) { engine in
            let before = engine.currentURL
            try await engine.submit(selector: selector)
            return try await InteractionReport.after(
                engine: engine, globals: globals, urlBefore: before, otherwise: "Form submitted")
        }
    }
}

struct Scroll: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Scroll the page")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "up, down, top, bottom, or a target") var target: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.scroll(target: target)
            return .plain("Scrolled: \(target)")
        }
    }
}

struct Hover: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Hover over an element")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: ArgumentHelp(stringLiteral: targetHelp)) var selector: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.hover(selector: selector, strict: globals.strict)
            return .plain("Hovering: \(selector)")
        }
    }
}

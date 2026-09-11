import ArgumentParser

struct Click: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Click an element")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector") var selector: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.click(selector: selector, strict: globals.strict)
            try await engine.waitFor(try globals.waitStrategy(default: .fetchquiet(maxMs: nil)))
            return .plain("Clicked: \(selector)")
        }
    }
}

struct Fill: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Fill a form field")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector") var selector: String
    @Argument(help: "Value to set") var value: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.fill(selector: selector, value: value, strict: globals.strict)
            return .plain("Filled \(selector) with value")
        }
    }
}

struct SelectOption: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "select", abstract: "Choose a <select> option")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "CSS selector") var selector: String
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
    @Argument(help: "CSS selector") var selector: String
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
    @Argument(help: "CSS selector") var selector: String
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
    @Argument(help: "CSS selector (optional)") var selector: String?
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.submit(selector: selector)
            return .plain("Form submitted")
        }
    }
}

struct Scroll: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Scroll the page")
    @OptionGroup var globals: GlobalOptions
    @Argument(help: "up, down, top, bottom, or CSS selector") var target: String
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
    @Argument(help: "CSS selector") var selector: String
    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            try await engine.hover(selector: selector, strict: globals.strict)
            return .plain("Hovering: \(selector)")
        }
    }
}

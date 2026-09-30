import ArgumentParser

/// Hand a live session to a person mid-task (a CAPTCHA, an MFA prompt), then
/// take it back. `login` does this only for a fresh page; these work on
/// whatever the session is already showing.
struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show the session's window so a person can use the page")
    @OptionGroup var globals: GlobalOptions
    @Option(name: .long, help: "Window size (WxH)") var size: String = "1280x800"

    func run() throws {
        // In-process, the window would close as soon as the command exits.
        if globals.noDaemon { throw PeriscopeError.argumentError(reason: "show needs the daemon; drop --no-daemon") }
        let (width, height) = parseViewport(size)
        CommandRunner.run(globals: globals) { engine in
            await engine.showWindow(width: width, height: height)
            return .plain("Showing session '\(globals.session)'. Run `periscope hide --session \(globals.session)` when done.")
        }
    }
}

struct Hide: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Hide the session's window again")
    @OptionGroup var globals: GlobalOptions

    func run() throws {
        CommandRunner.run(globals: globals) { engine in
            engine.hideWindow()
            return .plain("Hidden: \(engine.locationDescription)")
        }
    }
}

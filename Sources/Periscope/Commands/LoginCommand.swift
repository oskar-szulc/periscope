import AppKit
import ArgumentParser
import Foundation

struct Login: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a visible browser for manual login, then save the session"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "URL to navigate to for login")
    var url: String

    @Option(
        name: .long,
        help:
            "When login is done: selector:<css>, url:<text> or title:<text>; ! before the colon inverts (title!:Just a moment). Default: the URL path changes."
    )
    var until: String?

    func run() throws {
        let untilCondition = try until.map(UntilCondition.parse)
        guard let parsedURL = URL(string: url) else {
            throw PeriscopeError.argumentError(reason: "Invalid URL: \(url)")
        }

        let formatter = makeFormatter(json: globals.json)

        MainActor.assumeIsolated {
            AppRunner.run(json: globals.json) {
                do {
                    try await login(parsedURL, until: untilCondition, formatter: formatter)
                } catch {
                    let payload = ErrorPayload(error)
                    CommandRunner.emit(payload, formatter: formatter, globals: globals)
                    Foundation.exit(payload.exitCode)
                }
            }
        }
    }

    @MainActor
    private func login(
        _ parsedURL: URL, until untilCondition: UntilCondition?, formatter: OutputFormatting
    ) async throws {
        // A person needs longer than a page load; 0 waits until Ctrl-C.
        let timeoutSeconds = globals.timeout == 30 ? 120 : globals.timeout
        let (width, height) = globals.viewportSize
        let engine = BrowserEngine(viewportWidth: width, viewportHeight: height)
        engine.setUserAgent(globals.userAgent)

        // Pre-fill cookies from an existing session.
        if !globals.noSession {
            _ = try? await SessionRestore.restore(engine: engine, session: globals.session)
        }

        _ = try await engine.navigate(to: parsedURL)
        await engine.showWindow()
        FileHandle.standardError.write(
            Data("Log in manually. Periscope will detect when you're done.\n".utf8))

        do {
            try await withTimeout(seconds: timeoutSeconds) {
                try await engine.waitForLoginCompletion(until: untilCondition)
            }
        } catch PeriscopeError.timeout {
            let waited = untilCondition.map { "--until \($0) never held" } ?? "the URL path never changed"
            FileHandle.standardError.write(
                Data(
                    "\(waited). Page at timeout: \(engine.locationDescription). Pass --timeout <s> for longer, 0 to wait until Ctrl-C.\n"
                        .utf8))
            throw PeriscopeError.timeout(seconds: timeoutSeconds)
        }

        engine.hideWindow()

        if !globals.noSession {
            try await SessionRestore.save(engine: engine, session: globals.session, fallbackURL: url)
        }

        print(
            formatter.format(
                .plain(
                    "\(globals.noSession ? "Login done; not saved (--no-session)" : "Session '\(globals.session)' saved"). URL: \(engine.currentURL ?? url)"
                )))
        engine.close()
    }
}

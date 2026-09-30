import ArgumentParser
import Foundation
import AppKit

struct Login: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a visible browser for manual login, then save the session"
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "URL to navigate to for login")
    var url: String

    @Option(name: .long, help: "When login is done: selector:<css>, url:<text> or title:<text>; ! before the colon inverts (title!:Just a moment). Default: the URL path changes.")
    var until: String?

    func run() throws {
        let untilCondition = try until.map(UntilCondition.parse)
        guard let parsedURL = URL(string: url) else {
            throw PeriscopeError.argumentError(reason: "Invalid URL: \(url)")
        }

        // Capture everything as let for Sendable closure
        let isJson = globals.json
        let noSession = globals.noSession
        let sessionName = globals.session
        // A person needs longer than a page load; 0 waits until Ctrl-C.
        let timeoutSeconds = globals.timeout == 30 ? 120 : globals.timeout
        let viewportStr = globals.viewport
        let userAgent = globals.userAgent
        let (width, height) = globals.viewportSize
        let urlString = url
        let formatter = makeFormatter(json: isJson)

        MainActor.assumeIsolated {
            AppRunner.run(json: isJson) {
                do {
                    try await Self.executeLogin(
                        parsedURL: parsedURL,
                        urlString: urlString,
                        width: width,
                        height: height,
                        noSession: noSession,
                        sessionName: sessionName,
                        timeoutSeconds: timeoutSeconds,
                        viewportStr: viewportStr,
                        userAgent: userAgent,
                        untilCondition: untilCondition,
                        formatter: formatter,
                        isJson: isJson
                    )
                } catch {
                    let msg = (error as? PeriscopeError)?.description ?? error.localizedDescription
                    if isJson {
                        print(formatter.format(.error(msg)))
                    } else {
                        FileHandle.standardError.write(Data(("Error: " + msg + "\n").utf8))
                    }
                    Foundation.exit((error as? PeriscopeError)?.exitCode ?? 1)
                }
            }
        }
    }

    @MainActor
    private static func executeLogin(
        parsedURL: URL,
        urlString: String,
        width: Int,
        height: Int,
        noSession: Bool,
        sessionName: String,
        timeoutSeconds: Int,
        viewportStr: String,
        userAgent: String?,
        untilCondition: UntilCondition?,
        formatter: OutputFormatting,
        isJson: Bool
    ) async throws {
        let engine = BrowserEngine(viewportWidth: width, viewportHeight: height)
        engine.setUserAgent(userAgent)

        // Restore existing session if any (to pre-fill cookies)
        if !noSession {
            _ = try? await SessionRestore.restore(engine: engine, session: sessionName)
        }

        // Navigate to the login URL
        _ = try await engine.navigate(to: parsedURL)

        // Show the window for manual interaction
        engine.showWindow()

        // Print instructions to stderr
        FileHandle.standardError.write(
            Data("Log in manually. Periscope will detect when you're done.\n".utf8))

        // Wait for login completion with timeout
        do {
            try await withTimeout(seconds: timeoutSeconds) {
                try await engine.waitForLoginCompletion(initialURL: parsedURL, until: untilCondition)
            }
        } catch PeriscopeError.timeout {
            let waited = untilCondition.map { "--until \($0) never held" } ?? "the URL path never changed"
            FileHandle.standardError.write(Data(
                "\(waited). Page at timeout: \(engine.locationDescription). Pass --timeout <s> for longer, 0 to wait until Ctrl-C.\n".utf8))
            throw PeriscopeError.timeout(seconds: timeoutSeconds)
        }

        // Hide the window
        engine.hideWindow()

        // Save session
        if !noSession {
            try await SessionRestore.save(
                engine: engine, session: sessionName,
                viewport: viewportStr, fallbackURL: urlString)
        }

        print(formatter.format(
            .plain("Session '\(sessionName)' saved. URL: \(engine.currentURL ?? urlString)")))
        engine.close()
    }
}

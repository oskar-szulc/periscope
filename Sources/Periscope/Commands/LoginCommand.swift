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

    @Option(name: .long, help: "Condition to detect login completion: selector:<css> or url:<pattern>. Default: auto-detect URL change.")
    var until: String?

    func run() throws {
        guard let parsedURL = URL(string: url) else {
            throw PeriscopeError.argumentError(reason: "Invalid URL: \(url)")
        }

        // Capture everything as let for Sendable closure
        let isJson = globals.json
        let noSession = globals.noSession
        let sessionName = globals.session
        let timeoutSeconds = globals.timeout == 30 ? 120 : globals.timeout
        let viewportStr = globals.viewport
        let (width, height) = globals.viewportSize
        let untilCondition = until
        let urlString = url
        let formatter = makeFormatter(json: isJson)

        MainActor.assumeIsolated {
            AppRunner.run {
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
        untilCondition: String?,
        formatter: OutputFormatting,
        isJson: Bool
    ) async throws {
        let engine = BrowserEngine(viewportWidth: width, viewportHeight: height)

        // Restore existing session if any (to pre-fill cookies)
        if !noSession {
            let manager = SessionManager()
            if let state = try manager.loadState(session: sessionName),
               let existingURL = URL(string: state.url) {
                _ = try? await engine.navigate(to: existingURL)
                let cookies = try manager.loadCookies(session: sessionName)
                if !cookies.isEmpty {
                    let js = cookies.map { c in
                        "document.cookie = '\(c.name)=\(c.value); path=\(c.path); domain=\(c.domain)"
                        + (c.secure ? "; secure" : "") + "';"
                    }.joined(separator: "\n")
                    try? await engine.runJavaScriptVoid(js)
                }
            }
        }

        // Navigate to the login URL
        _ = try await engine.navigate(to: parsedURL)

        // Show the window for manual interaction
        engine.showWindow()

        // Print instructions to stderr
        FileHandle.standardError.write(
            Data("Log in manually. Periscope will detect when you're done.\n".utf8))

        // Wait for login completion with timeout
        try await withTimeout(seconds: timeoutSeconds) {
            try await engine.waitForLoginCompletion(
                initialURL: parsedURL,
                until: untilCondition
            )
        }

        // Hide the window
        engine.hideWindow()

        // Save session
        if !noSession {
            let manager = SessionManager()
            let sessionURL = engine.currentURL ?? urlString
            let sessionTitle = engine.currentTitle

            try manager.saveState(
                SessionState(url: sessionURL, title: sessionTitle, viewport: viewportStr),
                session: sessionName)

            if let cookieStr = try await engine.runJavaScript("document.cookie") as? String,
               !cookieStr.isEmpty {
                let host = URL(string: sessionURL)?.host ?? ""
                let cookies = cookieStr.split(separator: ";").map { pair in
                    let parts = pair.trimmingCharacters(in: .whitespaces)
                        .split(separator: "=", maxSplits: 1)
                    return PersistedCookie(
                        name: String(parts[0]),
                        value: parts.count > 1 ? String(parts[1]) : "",
                        domain: host, path: "/", expires: nil,
                        secure: false, httpOnly: false)
                }
                try manager.saveCookies(cookies, session: sessionName)
            }

            if let json = try await engine.runJavaScript(
                StorageManager.extractionScript()) as? String,
               let data = json.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data)
                   as? [String: String] {
                let origin = URL(string: sessionURL).map {
                    "\($0.scheme ?? "https")://\($0.host ?? "")"
                } ?? sessionURL
                try manager.saveStorage(
                    PersistedStorage(origin: origin, localStorage: dict),
                    session: sessionName)
            }
        }

        print(formatter.format(
            .plain("Session '\(sessionName)' saved. URL: \(engine.currentURL ?? urlString)")))
        engine.close()
    }
}

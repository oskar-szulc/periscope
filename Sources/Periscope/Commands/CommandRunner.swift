import Foundation
import AppKit

enum CommandRunner {
    typealias CommandBlock = @MainActor (BrowserEngine) async throws -> CommandResult

    static func run(globals: GlobalOptions, command: @escaping CommandBlock) {
        let formatter = makeFormatter(json: globals.json)
        let (width, height) = globals.viewportSize

        MainActor.assumeIsolated {
            AppRunner.run {
                let engine = await MainActor.run {
                    BrowserEngine(viewportWidth: width, viewportHeight: height)
                }

                do {
                    // Restore session if applicable
                    if !globals.noSession {
                        try await Self.restoreSession(engine: engine, session: globals.session)
                    }

                    // Execute command with timeout
                    let result = try await withTimeout(seconds: globals.timeout) {
                        try await command(engine)
                    }

                    // Save session if applicable
                    if !globals.noSession {
                        try await Self.saveSession(engine: engine, session: globals.session)
                    }

                    print(formatter.format(result))
                    await MainActor.run { engine.close() }
                } catch let error as PeriscopeError {
                    let output = formatter.format(.error(error.description))
                    if globals.json {
                        print(output)
                    } else {
                        FileHandle.standardError.write(Data((output + "\n").utf8))
                    }
                    await MainActor.run { engine.close() }
                    Foundation.exit(error.exitCode)
                } catch {
                    let output = formatter.format(.error(error.localizedDescription))
                    if globals.json {
                        print(output)
                    } else {
                        FileHandle.standardError.write(Data((output + "\n").utf8))
                    }
                    await MainActor.run { engine.close() }
                    Foundation.exit(1)
                }
            }
        }
    }

    @MainActor
    private static func restoreSession(engine: BrowserEngine, session: String) async throws {
        let manager = SessionManager()
        if let state = try manager.loadState(session: session),
           let url = URL(string: state.url) {
            _ = try await engine.navigate(to: url)

            let cookies = try manager.loadCookies(session: session)
            if !cookies.isEmpty {
                let js = cookies.map { c in
                    "document.cookie = '\(c.name)=\(c.value); path=\(c.path); domain=\(c.domain)"
                    + (c.secure ? "; secure" : "") + "';"
                }.joined(separator: "\n")
                _ = try await engine.runJavaScript(js)
            }

            if let storage = try manager.loadStorage(session: session) {
                _ = try await engine.runJavaScript(StorageManager.injectionScript(for: storage))
            }
        }
    }

    @MainActor
    private static func saveSession(engine: BrowserEngine, session: String) async throws {
        let manager = SessionManager()
        guard let url = engine.currentURL else { return }

        try manager.saveState(
            SessionState(url: url, title: engine.currentTitle, viewport: "1920x1080"),
            session: session)

        if let cookieStr = try await engine.runJavaScript("document.cookie") as? String, !cookieStr.isEmpty {
            let host = URL(string: url)?.host ?? ""
            let cookies = cookieStr.split(separator: ";").map { pair in
                let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                return PersistedCookie(
                    name: String(parts[0]),
                    value: parts.count > 1 ? String(parts[1]) : "",
                    domain: host, path: "/", expires: nil, secure: false, httpOnly: false)
            }
            try manager.saveCookies(cookies, session: session)
        }

        if let json = try await engine.runJavaScript(StorageManager.extractionScript()) as? String,
           let data = json.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            let origin = URL(string: url).map { "\($0.scheme ?? "https")://\($0.host ?? "")" } ?? url
            try manager.saveStorage(PersistedStorage(origin: origin, localStorage: dict), session: session)
        }
    }
}

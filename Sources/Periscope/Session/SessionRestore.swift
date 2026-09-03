import Foundation

/// Reading and writing a session's disk snapshot.
///
/// Extracted from `CommandRunner` so the one-shot path and the daemon share one
/// implementation. The difference between them is *when* this runs: one-shot calls
/// it around every command, the daemon calls it on cold start and eviction only.
enum SessionRestore {
    /// Reopen a session's last page so cookies and localStorage can be injected into it.
    ///
    /// A saved URL goes stale routinely — a stopped dev server, an expired share link —
    /// and it is only a convenience, never what the user asked for. Failing to reach it
    /// must not block the command they actually ran, so a navigation failure returns a
    /// warning instead of throwing. Cookie and storage injection needs a loaded page,
    /// so it is skipped in that case.
    ///
    /// - Returns: a warning to surface to the user, or nil if restore was clean.
    @MainActor
    static func restore(engine: BrowserEngine, session: String) async throws -> String? {
        let manager = SessionManager()
        guard let state = try manager.loadState(session: session),
              let url = URL(string: state.url) else { return nil }

        do {
            _ = try await engine.navigate(to: url)
        } catch let error as PeriscopeError {
            return "warning: session '\(session)' could not reopen \(state.url) "
                + "(\(error.description)); continuing without restored cookies and storage"
        }

        let cookies = try manager.loadCookies(session: session)
        if !cookies.isEmpty {
            let js = cookies.map { c in
                "document.cookie = '\(c.name)=\(c.value); path=\(c.path); domain=\(c.domain)"
                + (c.secure ? "; secure" : "") + "';"
            }.joined(separator: "\n")
            try await engine.runJavaScriptVoid(js)
        }

        if let storage = try manager.loadStorage(session: session) {
            try await engine.runJavaScriptVoid(StorageManager.injectionScript(for: storage))
        }
        return nil
    }

    @MainActor
    static func save(engine: BrowserEngine, session: String) async throws {
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

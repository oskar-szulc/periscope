import Foundation

/// Reading and writing a session's disk snapshot.
///
/// Extracted from `CommandRunner` so the one-shot path and the daemon share one
/// implementation. The difference between them is *when* this runs: one-shot calls
/// it around every command, the daemon calls it on cold start and eviction only.
///
/// Cookies go through WebKit's jar, not `document.cookie`: the jar covers every
/// host the session has visited and HttpOnly cookies, and it can be written
/// before any page is loaded. The old `document.cookie` snapshot saved only the
/// current page's readable cookies, which is how a session cookie got lost
/// across a daemon restart.
enum SessionRestore {
    /// Reopen a session: cookies first, then the last page so localStorage can be injected.
    ///
    /// A saved URL goes stale routinely — a stopped dev server, an expired share link —
    /// and it is only a convenience, never what the user asked for. Failing to reach it
    /// must not block the command they actually ran, so a navigation failure returns a
    /// warning instead of throwing. The cookies are already in the jar by then.
    ///
    /// - Returns: a warning to surface to the user, or nil if restore was clean.
    @MainActor
    static func restore(engine: BrowserEngine, session: String) async throws -> String? {
        let manager = SessionManager()
        let cookies = try (manager.read([PersistedCookie].self, "cookies.json", session: session) ?? [])
            .compactMap(\.httpCookie)
        if !cookies.isEmpty {
            await engine.setCookies(cookies)
        }

        guard let state = try manager.read(SessionState.self, "state.json", session: session),
            let url = URL(string: state.url)
        else { return nil }

        do {
            _ = try await engine.navigate(to: url)
        } catch let error as PeriscopeError {
            return "warning: session '\(session)' could not reopen \(state.url) "
                + "(\(error.description)); cookies restored, storage not"
        }

        if let storage = try manager.read(PersistedStorage.self, "storage.json", session: session) {
            let json = String(decoding: try JSONEncoder().encode(storage.localStorage), as: UTF8.self)
            try await engine.runJavaScriptVoid(
                "Object.entries(\(json)).forEach(([k, v]) => localStorage.setItem(k, v))")
        }
        return nil
    }

    @MainActor
    static func save(engine: BrowserEngine, session: String, fallbackURL: String? = nil) async throws {
        let manager = SessionManager()

        let cookies = await engine.allCookies().map(PersistedCookie.init)
        try manager.write(CookieStore.pruneExpired(cookies), "cookies.json", session: session)

        guard let url = engine.currentURL ?? fallbackURL else { return }
        try manager.write(SessionState(url: url), "state.json", session: session)

        if let dict: [String: String] = try await engine.runJavaScriptDecoded("JSON.stringify({...localStorage})") {
            try manager.write(PersistedStorage(localStorage: dict), "storage.json", session: session)
        }
    }
}

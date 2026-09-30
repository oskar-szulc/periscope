import Foundation

struct PersistedCookie: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: String?
    let secure: Bool
    let httpOnly: Bool
}

// In an extension so Swift still synthesises the memberwise init.
extension PersistedCookie {
    /// Snapshot of a jar cookie with every attribute that matters on restore.
    /// A session cookie has no expiry and is kept; the jar would have kept it too.
    init(_ cookie: HTTPCookie) {
        self.init(
            name: cookie.name, value: cookie.value, domain: cookie.domain, path: cookie.path,
            expires: cookie.expiresDate.map(CookieStore.isoFormatter.string(from:)),
            secure: cookie.isSecure, httpOnly: cookie.isHTTPOnly)
    }

    var httpCookie: HTTPCookie? {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path,
        ]
        if secure { props[.secure] = "TRUE" }
        if httpOnly { props[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let expires, let date = CookieStore.isoFormatter.date(from: expires) {
            props[.expires] = date
        }
        return HTTPCookie(properties: props)
    }
}

enum CookieStore {
    /// `.withInternetDateTime` is the default format.
    nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    /// A session cookie (no expiry) is kept.
    static func pruneExpired(_ cookies: [PersistedCookie]) -> [PersistedCookie] {
        let now = Date()
        return cookies.filter { $0.expires.flatMap(isoFormatter.date(from:)).map { $0 > now } ?? true }
    }
}

import Foundation

struct PersistedCookie: Codable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: String?
    let secure: Bool
    let httpOnly: Bool

    init(
        name: String, value: String, domain: String, path: String,
        expires: String?, secure: Bool, httpOnly: Bool
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.secure = secure
        self.httpOnly = httpOnly
    }

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
    nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func serialize(_ cookies: [PersistedCookie]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(cookies)
    }

    static func deserialize(_ data: Data) throws -> [PersistedCookie] {
        try JSONDecoder().decode([PersistedCookie].self, from: data)
    }

    static func pruneExpired(_ cookies: [PersistedCookie]) -> [PersistedCookie] {
        let now = Date()
        return cookies.filter { cookie in
            guard let expires = cookie.expires,
                let date = isoFormatter.date(from: expires)
            else {
                return true
            }
            return date > now
        }
    }
}

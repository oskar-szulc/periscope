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

enum CookieStore {
    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
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
                  let date = isoFormatter.date(from: expires) else {
                return true
            }
            return date > now
        }
    }
}

/// Split a `document.cookie` string into name/value pairs.
///
/// The same split-trim-split idiom had been written out in three places
/// (session save, `cookie list`, and login).
func parseDocumentCookie(_ raw: String) -> [(name: String, value: String)] {
    raw.split(separator: ";").compactMap { pair in
        let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
        guard let name = parts.first else { return nil }
        return (String(name), parts.count > 1 ? String(parts[1]) : "")
    }
}

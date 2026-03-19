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

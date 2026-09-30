import Foundation
import Testing

@testable import Periscope

@Suite("CookieStore")
struct CookieStoreTests {
    @Test func serializeAndDeserialize() throws {
        let cookies = [
            PersistedCookie(
                name: "session_id", value: "abc123", domain: ".example.com",
                path: "/", expires: "2026-04-19T00:00:00Z", secure: true, httpOnly: true),
            PersistedCookie(
                name: "theme", value: "dark", domain: "example.com",
                path: "/", expires: nil, secure: false, httpOnly: false),
        ]
        let data = try CookieStore.serialize(cookies)
        let decoded = try CookieStore.deserialize(data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "session_id")
        #expect(decoded[0].secure == true)
        #expect(decoded[1].name == "theme")
        #expect(decoded[1].expires == nil)
    }

    @Test func prunesExpiredCookies() throws {
        let cookies = [
            PersistedCookie(
                name: "expired", value: "old", domain: ".example.com",
                path: "/", expires: "2020-01-01T00:00:00Z", secure: false, httpOnly: false),
            PersistedCookie(
                name: "valid", value: "new", domain: ".example.com",
                path: "/", expires: "2030-01-01T00:00:00Z", secure: false, httpOnly: false),
        ]
        let pruned = CookieStore.pruneExpired(cookies)
        #expect(pruned.count == 1)
        #expect(pruned[0].name == "valid")
    }
}

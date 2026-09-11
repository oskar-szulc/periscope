import Testing
import Foundation
@testable import Periscope

@Suite("Cookie jar round trip")
struct CookieJarTests {
    // Foundation caps cookie lifetime at 400 days, so tests use a nearer expiry.
    private let soon = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 30 * 86400).rounded(.down))

    @Test func httpCookieBecomesPersistedWithAllAttributes() throws {
        let cookie = try #require(HTTPCookie(properties: [
            .name: "sid", .value: "abc", .domain: ".example.com", .path: "/app",
            .secure: "TRUE", .expires: soon,
        ]))
        let persisted = PersistedCookie(cookie)
        #expect(persisted.name == "sid")
        #expect(persisted.domain == ".example.com")
        #expect(persisted.path == "/app")
        #expect(persisted.secure == true)
        #expect(persisted.expires == CookieStore.isoFormatter.string(from: soon))
    }

    @Test func sessionCookieKeepsNilExpiryAndRoundTrips() throws {
        let cookie = try #require(HTTPCookie(properties: [
            .name: "probe", .value: "ps1", .domain: "httpbin.org", .path: "/",
        ]))
        let persisted = PersistedCookie(cookie)
        #expect(persisted.expires == nil)
        let back = try #require(persisted.httpCookie)
        #expect(back.name == "probe")
        #expect(back.value == "ps1")
        #expect(back.domain == "httpbin.org")
        #expect(back.expiresDate == nil)
    }

    @Test func httpOnlyAndExpirySurviveTheRoundTrip() throws {
        let persisted = PersistedCookie(
            name: "s", value: "v", domain: ".example.com", path: "/",
            expires: CookieStore.isoFormatter.string(from: soon), secure: true, httpOnly: true)
        let cookie = try #require(persisted.httpCookie)
        #expect(cookie.isHTTPOnly == true)
        #expect(cookie.isSecure == true)
        #expect(cookie.expiresDate == soon)
    }
}

import Foundation
import Testing

@testable import Periscope

@Suite("login --until")
struct UntilConditionTests {
    @Test func parsesEachKindAndNegation() throws {
        #expect(try UntilCondition.parse("selector:tr.row") == .init(kind: .selector, negated: false, value: "tr.row"))
        #expect(try UntilCondition.parse("title!:Just a moment") == .init(kind: .title, negated: true, value: "Just a moment"))
        #expect(try UntilCondition.parse("url:/home?x=1:2").value == "/home?x=1:2")  // only the first colon splits
    }

    @Test func rejectsWhatUsedToLoopUntilTimeout() {
        for bad in ["tr.mbgen", "css:tr", "selector:", "!:x"] {
            #expect(throws: PeriscopeError.self) { try UntilCondition.parse(bad) }
        }
    }

    @Test func negationWaitsForTheChallengeToGo() throws {
        let gone = try UntilCondition.parse("title!:just a moment")
        #expect(!gone.holds(url: "https://x.test", title: "Just a moment...", matches: false))
        #expect(gone.holds(url: "https://x.test", title: "My collection", matches: false))
        #expect(try UntilCondition.parse("selector:tr").holds(url: "", title: "", matches: true))
    }
}

@Suite("navigate --wait-challenge")
struct WaitChallengeTests {
    /// A page that looks like Cloudflare's interstitial, then becomes the real
    /// page on its own, as a managed challenge does.
    private func challengeFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("challenge-\(UUID().uuidString).html")
        try """
        <html><head><title>Just a moment...</title></head><body><p>Verifying you are human.</p>
        <script>setTimeout(function() {
            document.title = 'Real page'; document.body.innerHTML = '<p>the content</p>';
        }, 1500);</script></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test @MainActor func failsAsBlockedWithoutWaiting() async throws {
        let engine = BrowserEngine(viewportWidth: 800, viewportHeight: 600)
        defer { engine.close() }
        _ = try await engine.navigate(to: try challengeFixture())
        await #expect(throws: PeriscopeError.self) {
            try await NavigationReport.make(engine: engine, wait: .none, fallbackURL: "")
        }
    }

    @Test @MainActor func waitsForTheChallengeToClear() async throws {
        let engine = BrowserEngine(viewportWidth: 800, viewportHeight: 600)
        defer { engine.close() }
        _ = try await engine.navigate(to: try challengeFixture())
        let result = try await NavigationReport.make(engine: engine, wait: .none, fallbackURL: "", challengeSeconds: 6)
        guard case .navigate(let title, _, _, _, _) = result else { Issue.record("not a navigate result"); return }
        #expect(title == "Real page")
    }
}

@Suite("login completion")
struct LoginCompletionTests {
    private func page(_ name: String, _ body: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).html")
        try "<html><body>\(body)</body></html>".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// `/wp-admin/` redirects to `/wp-login.php` before the person sees it: the
    /// page it landed on is the baseline, not the URL that was asked for.
    @Test @MainActor func aRedirectBeforeTheWindowOpensIsNotALogin() async throws {
        let engine = BrowserEngine(viewportWidth: 800, viewportHeight: 600)
        defer { engine.close() }
        let requested = try page("admin", "")
        let dashboard = try page("dashboard", "")
        _ = try await engine.navigate(to: try page("login", "<form></form>"))
        await #expect(throws: PeriscopeError.self) {
            try await withTimeout(seconds: 3) {
                try await engine.waitForLoginCompletion(initialURL: requested, until: nil)
            }
        }
        _ = try await engine.runJavaScript("location.href = '\(dashboard.absoluteString)'")
        try await withTimeout(seconds: 5) {
            try await engine.waitForLoginCompletion(initialURL: requested, until: nil)
        }
    }
}

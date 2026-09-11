import Testing
import Foundation
@testable import Periscope

@Suite("requests and console output")
struct DiagnosticsFormattingTests {
    @Test func requestsTextOutputDistinguishesStatusPendingAndFailed() {
        let items = [
            RequestItem(method: "GET", url: "https://jobs.ashbyhq.com/felix", status: 200, kind: "document", durationMs: nil, error: nil),
            RequestItem(method: "POST", url: "https://api.ashbyhq.com/graphql", status: 200, kind: "fetch", durationMs: 143, error: nil),
            RequestItem(method: "GET", url: "https://x.test/boom", status: nil, kind: "xhr", durationMs: 12, error: "NetworkError"),
            RequestItem(method: "GET", url: "https://x.test/never", status: nil, kind: "xhr", durationMs: nil, error: nil),
        ]
        let out = TextFormatter().format(.requests(items))
        #expect(out == """
        GET https://jobs.ashbyhq.com/felix => 200 (document)
        POST https://api.ashbyhq.com/graphql => 200 (fetch, 143ms)
        GET https://x.test/boom => failed (xhr, 12ms: NetworkError)
        GET https://x.test/never => pending (xhr)
        """)
    }

    @Test func requestsJSONCarriesStatusAndError() throws {
        let out = JSONFormatter().format(.requests([
            RequestItem(method: "GET", url: "https://a/", status: 404, kind: "fetch", durationMs: 5, error: nil),
            RequestItem(method: "GET", url: "https://b/", status: nil, kind: "xhr", durationMs: nil, error: "TypeError: Failed to fetch"),
        ]))
        let json = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
        let items = json["requests"] as! [[String: Any]]
        #expect(items[0]["status"] as? Int == 404)
        #expect(items[0]["error"] is NSNull)
        #expect(items[1]["error"] as? String == "TypeError: Failed to fetch")
    }

    @Test func consoleTextOutput() {
        let out = TextFormatter().format(.console([
            ConsoleItem(level: "error", text: "TypeError: x is null", source: "app.js:12"),
            ConsoleItem(level: "log", text: "ready", source: nil),
        ]))
        #expect(out == "[error] TypeError: x is null (app.js:12)\n[log] ready")
    }

    @Test func emptyDiagnosticsSaySo() {
        #expect(TextFormatter().format(.requests([])) == "No requests recorded.")
        #expect(TextFormatter().format(.console([])) == "No console messages.")
    }
}

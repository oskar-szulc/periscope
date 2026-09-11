import Testing
import Foundation
@testable import Periscope

@Suite("requests and console output")
struct DiagnosticsFormattingTests {
    @Test func requestsTextOutput() {
        let items = [
            RequestItem(method: "GET", url: "https://jobs.ashbyhq.com/felix", status: 200, kind: "document", durationMs: nil),
            RequestItem(method: "POST", url: "https://api.ashbyhq.com/graphql", status: 200, kind: "fetch", durationMs: 143),
            RequestItem(method: "GET", url: "https://x.test/never", status: nil, kind: "xhr", durationMs: nil),
        ]
        let out = TextFormatter().format(.requests(items))
        #expect(out == """
        GET https://jobs.ashbyhq.com/felix => 200 (document)
        POST https://api.ashbyhq.com/graphql => 200 (fetch, 143ms)
        GET https://x.test/never => pending (xhr)
        """)
    }

    @Test func requestsJSONOutput() throws {
        let out = JSONFormatter().format(.requests([
            RequestItem(method: "GET", url: "https://a/", status: 404, kind: "fetch", durationMs: 5)]))
        let json = try JSONSerialization.jsonObject(with: Data(out.utf8)) as! [String: Any]
        let first = (json["requests"] as! [[String: Any]])[0]
        #expect(first["status"] as? Int == 404)
        #expect(first["kind"] as? String == "fetch")
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

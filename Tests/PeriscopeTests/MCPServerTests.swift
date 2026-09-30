import Foundation
import Testing

@testable import Periscope

@Suite("mcp server")
struct MCPServerTests {
    /// Records the argument vector each tool call would have run.
    final class Calls: @unchecked Sendable { var last: [String] = [] }

    private func server(status: Int32 = 0, stdout: String = "ok", stderr: String = "", calls: Calls = Calls()) -> MCPServer {
        MCPServer { args in
            calls.last = args
            return .init(status: status, stdout: Data(stdout.utf8), stderr: stderr)
        }
    }

    private func call(_ s: MCPServer, _ method: String, _ params: [String: Any] = [:], id: Any = 1) -> [String: Any] {
        s.handle(["jsonrpc": "2.0", "id": id, "method": method, "params": params]) ?? [:]
    }

    @Test func legacyInitializeEchoesAKnownVersion() {
        let r = call(server(), "initialize", ["protocolVersion": "2025-06-18"])["result"] as? [String: Any]
        #expect(r?["protocolVersion"] as? String == "2025-06-18")
        #expect((r?["serverInfo"] as? [String: String])?["name"] == "periscope")
        #expect(r?["capabilities"] as? [String: Any] != nil)
        let unknown = call(server(), "initialize", ["protocolVersion": "1999-01-01"])["result"] as? [String: Any]
        #expect(unknown?["protocolVersion"] as? String == MCPServer.legacyVersions[0])
    }

    @Test func notificationsGetNoReply() {
        #expect(server().handle(["jsonrpc": "2.0", "method": "notifications/initialized"]) == nil)
    }

    @Test func modernDiscoverAndVersionRejection() {
        let modern = ["_meta": ["io.modelcontextprotocol/protocolVersion": "2026-07-28"]]
        let r = call(server(), "server/discover", modern)["result"] as? [String: Any]
        #expect((r?["supportedVersions"] as? [String])?.contains("2026-07-28") == true)
        #expect(r?["resultType"] as? String == "complete")
        let bad = call(server(), "tools/list", ["_meta": ["io.modelcontextprotocol/protocolVersion": "1900-01-01"]])
        #expect((bad["error"] as? [String: Any])?["code"] as? Int == -32022)
    }

    @Test func toolsHaveSchemasWithASession() {
        let tools = (call(server(), "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        #expect(tools.count == MCPServer.tools.count)
        let navigate = tools.first { $0["name"] as? String == "navigate" }
        let schema = navigate?["inputSchema"] as? [String: Any]
        #expect(schema?["required"] as? [String] == ["url"])
        #expect((schema?["properties"] as? [String: Any])?["session"] != nil)
    }

    @Test func callsMapToTheCommandLine() {
        let calls = Calls()
        let s = server(calls: calls)
        _ = call(s, "tools/call", ["name": "navigate", "arguments": ["url": "https://x.test", "wait_challenge": 20]])
        #expect(calls.last == ["navigate", "https://x.test", "--wait-challenge", "20", "--timeout", "40", "--session", "mcp"])
        _ = call(s, "tools/call", ["name": "extract", "arguments": ["fields": "title, url", "session": "jobs"]])
        #expect(calls.last == ["extract", "title, url", "--session", "jobs"])
        _ = call(s, "tools/call", ["name": "fill", "arguments": ["target": "label:Email", "value": "a@b.c", "submit": true]])
        #expect(calls.last == ["fill", "label:Email", "a@b.c", "--submit", "--session", "mcp"])
    }

    @Test func failuresAreToolErrorsAndBadCallsAreProtocolErrors() {
        let failed =
            call(
                server(status: 5, stdout: "", stderr: "Error: Blocked by cloudflare-challenge"), "tools/call",
                ["name": "navigate", "arguments": ["url": "https://x.test"]])["result"] as? [String: Any]
        #expect(failed?["isError"] as? Bool == true)
        let text = (failed?["content"] as? [[String: Any]])?.first?["text"] as? String
        #expect(text?.contains("Blocked by") == true)
        #expect((call(server(), "tools/call", ["name": "nope"])["error"] as? [String: Any])?["code"] as? Int == -32602)
        #expect(
            (call(server(), "tools/call", ["name": "click", "arguments": [:]])["error"] as? [String: Any])?["code"] as? Int
                == -32602)
    }

    @Test func screenshotsComeBackAsImages() {
        let png = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let r = call(server(stdout: png), "tools/call", ["name": "screenshot", "arguments": [:]])["result"] as? [String: Any]
        let first = (r?["content"] as? [[String: Any]])?.first
        #expect(first?["type"] as? String == "image")
        #expect(first?["mimeType"] as? String == "image/png")
    }

    @Test func longResultsArePagedWithAContinuation() {
        let long = String(repeating: "a", count: 50)
        let first =
            call(server(stdout: long), "tools/call", ["name": "text", "arguments": ["max_chars": 20]])["result"] as? [String: Any]
        let text = (first?["content"] as? [[String: Any]])?.first?["text"] as? String ?? ""
        #expect(text.hasPrefix(String(repeating: "a", count: 20) + "\n\n[cut: characters 0–20 of 50; call again with offset=20"))
        let last =
            call(server(stdout: long), "tools/call", ["name": "text", "arguments": ["max_chars": 20, "offset": 40]])["result"]
            as? [String: Any]
        #expect(
            ((last?["content"] as? [[String: Any]])?.first?["text"] as? String)?.hasSuffix(
                "[characters 40–50 of 50; this is the end]") == true)
        // Short results and non-paged tools are untouched.
        let short = call(server(stdout: "hi"), "tools/call", ["name": "text", "arguments": [:]])["result"] as? [String: Any]
        #expect((short?["content"] as? [[String: Any]])?.first?["text"] as? String == "hi")
    }

    @Test func textOptionsMapToFlags() {
        let calls = Calls()
        _ = call(server(calls: calls), "tools/call", ["name": "text", "arguments": ["links": false, "images": true]])
        #expect(calls.last == ["text", "--no-links", "--images", "--session", "mcp"])
        let tools = (call(server(), "tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]] ?? []
        let props =
            (tools.first { $0["name"] as? String == "text" }?["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]
        #expect(props?["max_chars"] != nil && props?["offset"] != nil)
    }
}

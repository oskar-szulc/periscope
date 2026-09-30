import ArgumentParser
import Foundation

/// `periscope mcp`: periscope's commands as MCP tools over stdio, for agents
/// that speak MCP rather than a shell.
///
/// Each tool call runs this same binary with the equivalent arguments, so a
/// tool behaves exactly like the command: the daemon keeps its session, the
/// sandbox check and exit codes apply, and nothing is implemented twice.
struct MCP: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Serve periscope's commands as MCP tools over stdio",
        discussion: "Register it with an MCP client as the command `periscope mcp`.")

    func run() throws {
        MCPServer(runTool: MCPServer.subprocess).serve()
    }
}

struct MCPServer {
    /// What one command printed and how it exited.
    struct Output {
        var status: Int32
        var stdout: Data
        var stderr: String
    }

    var runTool: ([String]) -> Output

    static let modernVersions = ["2026-07-28"]
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let instructions = """
        A real Safari-engine browser. Start with navigate (it keeps the page open in a named \
        session, default "mcp"), then read with state (what can be clicked), text (the content \
        as markdown) or extract (the page's repeated items as JSON). On a busy page start with \
        state or extract: text on a news front page runs to tens of thousands of characters. \
        Long results are cut at max_chars, with the offset to continue from. Targets are CSS or \
        what a person sees: "text:Next", "label:Email", "role:button name=Sign in", or @N from \
        state. A bot-check page fails with "Blocked by"; navigate's wait_challenge gives it time.
        """

    // MARK: - Tools

    struct Tool: Sendable {
        var name: String
        var description: String
        /// (name, JSON type, description, required)
        var parameters: [(String, String, String, Bool)]
        var arguments: @Sendable ([String: Any]) -> [String]
        /// Returns text that can outgrow a client's tool-result limit: takes
        /// max_chars and offset.
        var paged = false
    }

    static let defaultMaxChars = 20_000
    static let pagingParameters = [
        ("max_chars", "integer", "Cut the result at this many characters (default \(defaultMaxChars))", false),
        ("offset", "integer", "Start at this character, to read on past a cut", false),
    ]

    static let tools: [Tool] = [
        Tool(
            name: "navigate", description: "Open a URL and report its title, HTTP status and text size.",
            parameters: [
                ("url", "string", "The URL to open", true),
                ("wait_challenge", "integer", "Seconds to let a bot-check page clear itself", false),
            ],
            arguments: { a in
                var args = ["navigate", a["url"] as? String ?? ""]
                if let s = a["wait_challenge"] as? Int, s > 0 { args += ["--wait-challenge", "\(s)", "--timeout", "\(s + 20)"] }
                return args
            }),
        Tool(
            name: "state",
            description: "The page's URL, headings, content and every clickable element, each with a selector and an @N target.",
            parameters: [("match", "string", "Only elements matching this regex", false)],
            arguments: { a in ["state"] + opt("--match", a["match"]) }, paged: true),
        Tool(
            name: "text",
            description:
                "The page's main content as markdown. Images are left out (alt text kept); links: false also drops link URLs, which are much of a busy page. On a large page, state or extract is a better start.",
            parameters: [
                ("selector", "string", "Only this element's content", false),
                ("links", "boolean", "Keep link URLs (default true)", false),
                ("images", "boolean", "Keep image markup (default false)", false),
            ],
            arguments: { a in
                ["text"] + ((a["selector"] as? String).map { [$0] } ?? [])
                    + ((a["links"] as? Bool) == false ? ["--no-links"] : [])
                    + ((a["images"] as? Bool ?? false) ? ["--images"] : [])
            }, paged: true),
        Tool(
            name: "extract",
            description:
                "The page's records as JSON: repeated items (cards, results, table rows), schema.org data and the next-page link. With fields, the on-device model maps items to them.",
            parameters: [
                ("fields", "string", "Comma-separated fields to extract per item, e.g. \"title, price, url\"", false),
                ("items", "string", "Target for the records, if detection picks the wrong ones", false),
                ("from", "string", "Only look inside this element", false),
            ],
            arguments: { a in
                ["extract"] + ((a["fields"] as? String).map { [$0] } ?? []) + opt("--items", a["items"])
                    + opt("--from", a["from"])
            }, paged: true),
        Tool(
            name: "links", description: "Every link on the page as an absolute URL.",
            parameters: [("match", "string", "Only URLs matching this regex", false)],
            arguments: { a in ["links"] + opt("--match", a["match"]) }, paged: true),
        Tool(
            name: "screenshot", description: "A PNG of the page as displayed.",
            parameters: [("full", "boolean", "The whole page, not just the viewport", false)],
            arguments: { a in ["screenshot"] + ((a["full"] as? Bool ?? false) ? ["--full"] : []) }),
        Tool(
            name: "click", description: "Click an element; reports the new page if it navigated.",
            parameters: [("target", "string", "CSS, text:<text>, label:<label>, role:<role> name=<name>, or @N", true)],
            arguments: { a in ["click", a["target"] as? String ?? ""] }),
        Tool(
            name: "fill", description: "Set a form field's value directly.",
            parameters: [
                ("target", "string", "The field", true), ("value", "string", "The value", true),
                ("submit", "boolean", "Press Enter afterwards", false),
            ],
            arguments: { a in
                ["fill", a["target"] as? String ?? "", a["value"] as? String ?? ""]
                    + ((a["submit"] as? Bool ?? false) ? ["--submit"] : [])
            }),
        Tool(
            name: "type", description: "Type into a field with real key events, as a person would.",
            parameters: [
                ("target", "string", "The field", true), ("text", "string", "Text to type", true),
                ("submit", "boolean", "Press Enter afterwards", false),
            ],
            arguments: { a in
                ["type", a["target"] as? String ?? "", a["text"] as? String ?? ""]
                    + ((a["submit"] as? Bool ?? false) ? ["--submit"] : [])
            }),
        Tool(
            name: "scroll", description: "Scroll the page, for lazy-loaded content.",
            parameters: [("target", "string", "up, down, top, bottom, or an element to scroll to", true)],
            arguments: { a in ["scroll", a["target"] as? String ?? ""] }),
        Tool(
            name: "eval", description: "Run JavaScript in the page and return the result.",
            parameters: [("code", "string", "A JavaScript expression or statements", true)],
            arguments: { a in ["eval", a["code"] as? String ?? ""] }, paged: true),
    ]

    private static func opt(_ flag: String, _ value: Any?) -> [String] {
        (value as? String).map { [flag, $0] } ?? []
    }

    static let sessionParameter = ("session", "string", "Named browser session; defaults to \"mcp\"", false)

    static func schema(_ tool: Tool) -> [String: Any] {
        let parameters = tool.parameters + (tool.paged ? pagingParameters : []) + [sessionParameter]
        var properties: [String: Any] = [:]
        for (name, type, description, _) in parameters { properties[name] = ["type": type, "description": description] }
        return [
            "name": tool.name, "description": tool.description,
            "inputSchema": [
                "type": "object", "properties": properties,
                "required": parameters.filter(\.3).map(\.0),
            ] as [String: Any],
        ]
    }

    // MARK: - JSON-RPC

    /// One message in, at most one reply out (notifications get none).
    func handle(_ message: [String: Any]) -> [String: Any]? {
        guard let method = message["method"] as? String else { return nil }  // a response to us: ignore
        guard let id = message["id"] else { return nil }  // notification
        let params = message["params"] as? [String: Any] ?? [:]
        let meta = params["_meta"] as? [String: Any]
        // A modern (stateless) request names its version on every call.
        let version = meta?["io.modelcontextprotocol/protocolVersion"] as? String
        if let version, !Self.modernVersions.contains(version) {
            return Self.error(
                id, -32022, "Unsupported protocol version",
                data: ["supported": Self.modernVersions + Self.legacyVersions, "requested": version])
        }
        let modern = version != nil
        func result(_ body: [String: Any]) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "result": modern ? body.merging(["resultType": "complete"]) { a, _ in a } : body]
        }
        let serverInfo = ["name": "periscope", "version": PeriscopeRoot.configuration.version]
        let capabilities = ["tools": [String: Any]()]

        switch method {
        case "initialize":  // legacy handshake
            let requested = params["protocolVersion"] as? String ?? ""
            return result([
                "protocolVersion": Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0],
                "capabilities": capabilities, "serverInfo": serverInfo, "instructions": Self.instructions,
            ])
        case "server/discover":
            return result([
                "supportedVersions": Self.modernVersions + Self.legacyVersions, "capabilities": capabilities,
                "_meta": ["io.modelcontextprotocol/serverInfo": serverInfo], "instructions": Self.instructions,
            ])
        case "ping":
            return result([:])
        case "tools/list":
            var body: [String: Any] = ["tools": Self.tools.map(Self.schema)]
            if modern { body["ttlMs"] = 3_600_000; body["cacheScope"] = "public" }
            return result(body)
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard let tool = Self.tools.first(where: { $0.name == name }) else {
                return Self.error(id, -32602, "Unknown tool: \(name)")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let missing = tool.parameters.filter { $0.3 && arguments[$0.0] == nil }.map(\.0)
            guard missing.isEmpty else {
                return Self.error(id, -32602, "\(name) needs: \(missing.joined(separator: ", "))")
            }
            let session = arguments["session"] as? String ?? "mcp"
            let output = runTool(tool.arguments(arguments) + ["--session", session])
            var body = Self.toolResult(tool: name, output)
            if tool.paged {
                body = Self.paged(
                    body, offset: arguments["offset"] as? Int ?? 0,
                    maxChars: arguments["max_chars"] as? Int ?? Self.defaultMaxChars)
            }
            return result(body)
        default:
            return Self.error(id, -32601, "Method not found: \(method)")
        }
    }

    static func toolResult(tool: String, _ output: Output) -> [String: Any] {
        let text = String(data: output.stdout, encoding: .utf8) ?? ""
        let warnings = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.status != 0 {
            let message = [warnings, text.trimmingCharacters(in: .whitespacesAndNewlines)].filter { !$0.isEmpty }
            return ["isError": true, "content": [["type": "text", "text": message.joined(separator: "\n")]]]
        }
        var content: [[String: Any]]
        if tool == "screenshot", let png = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            content = [["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]]
        } else {
            content = [["type": "text", "text": text]]
        }
        if !warnings.isEmpty { content.append(["type": "text", "text": warnings]) }
        return ["content": content]
    }

    /// Cuts the first text item to [offset, offset + maxChars) and says where
    /// it was cut, so an agent reads a busy page in pieces instead of the
    /// client dropping a result over its size limit (seen: text on onet.pl,
    /// 60k chars, saved to a file the agent then had to strip with sed).
    static func paged(_ body: [String: Any], offset: Int, maxChars: Int) -> [String: Any] {
        guard var content = body["content"] as? [[String: Any]], let text = content.first?["text"] as? String,
            maxChars > 0
        else { return body }
        let total = text.count
        let start = min(max(offset, 0), total)
        let end = min(start + maxChars, total)
        guard start > 0 || end < total else { return body }
        let from = text.index(text.startIndex, offsetBy: start)
        let to = text.index(from, offsetBy: end - start)
        var piece = String(text[from..<to])
        piece +=
            end < total
            ? "\n\n[cut: characters \(start)–\(end) of \(total); call again with offset=\(end) for more]"
            : "\n\n[characters \(start)–\(end) of \(total); this is the end]"
        content[0]["text"] = piece
        var out = body
        out["content"] = content
        return out
    }

    static func error(_ id: Any, _ code: Int, _ message: String, data: [String: Any]? = nil) -> [String: Any] {
        var error: [String: Any] = ["code": code, "message": message]
        if let data { error["data"] = data }
        return ["jsonrpc": "2.0", "id": id, "error": error]
    }

    // MARK: - Transport

    /// Newline-delimited JSON-RPC on stdin/stdout, one request at a time.
    func serve() {
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8),
                let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                write(Self.error(NSNull(), -32700, "Parse error"))
                continue
            }
            if let reply = handle(message) { write(reply) }
        }
    }

    private func write(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    /// Runs this binary with `arguments`. stderr goes to a temp file rather
    /// than a second pipe, so a chatty command cannot fill one pipe and stall
    /// while the other is read.
    static func subprocess(_ arguments: [String]) -> Output {
        guard let executable = Bundle.main.executableURL else {
            return Output(status: 1, stdout: Data(), stderr: "no executable")
        }
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("periscope-mcp-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errURL) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle(forWritingAtPath: errURL.path)
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return Output(status: 1, stdout: Data(), stderr: "\(error)") }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errText = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        return Output(status: process.terminationStatus, stdout: outData, stderr: errText)
    }
}

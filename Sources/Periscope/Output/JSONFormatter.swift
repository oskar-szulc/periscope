import Foundation

struct JSONFormatter: OutputFormatting {
    /// `--fields`: keep only these top-level keys (plus `ok`); for `state`,
    /// keys of the state object. Applied to the final JSON, so every command,
    /// `extract`'s raw JSON included, filters the same way.
    var fields: [String]? = nil

    func format(_ result: CommandResult) -> String {
        let json = render(result)
        guard let fields, !fields.isEmpty,
            let data = json.data(using: .utf8),
            var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return json }
        func keep(_ dict: [String: Any]) -> [String: Any] {
            dict.filter { fields.contains($0.key) || $0.key == "ok" }
        }
        if let state = object["state"] as? [String: Any] { object["state"] = keep(state) } else { object = keep(object) }
        guard let out = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return json }
        return String(data: out, encoding: .utf8) ?? json
    }

    private func render(_ result: CommandResult) -> String {
        let dict: [String: Any]
        switch result {
        case .navigate(let title, let url, let status, let textChars, let htmlChars):
            dict = [
                "ok": true, "title": title as Any, "url": url,
                "status": status as Any, "textChars": textChars, "htmlChars": htmlChars,
            ]
        case .extract(let content):
            dict = ["ok": true, "content": content]
        case .html(let content):
            dict = ["ok": true, "html": content]
        case .links(let items):
            dict = ["ok": true, "links": items.map { ["text": $0.text, "url": $0.url] }]
        case .elements(let items):
            dict = [
                "ok": true,
                "elements": items.map {
                    [
                        "index": $0.index, "tag": $0.tag, "id": $0.id as Any,
                        "classes": $0.classes, "text": $0.text,
                    ] as [String: Any]
                },
            ]
        case .jsResult(let value):
            dict = ["ok": true, "value": value as Any]
        case .screenshot(let path):
            dict = ["ok": true, "path": path]
        case .cookies(let items):
            dict = [
                "ok": true,
                "cookies": items.map {
                    ["name": $0.name, "value": $0.value, "domain": $0.domain]
                },
            ]
        case .sessionList(let names):
            dict = ["ok": true, "sessions": names]
        case .history(let items):
            dict = [
                "ok": true,
                "history": items.map {
                    [
                        "title": $0.title as Any, "url": $0.url,
                        "current": $0.isCurrent,
                    ] as [String: Any]
                },
            ]
        case .requests(let items):
            dict = [
                "ok": true,
                "requests": items.map {
                    [
                        "method": $0.method, "url": $0.url, "status": $0.status as Any,
                        "kind": $0.kind, "durationMs": $0.durationMs as Any,
                        "error": $0.error as Any,
                    ] as [String: Any]
                },
            ]
        case .console(let items):
            dict = [
                "ok": true,
                "console": items.map {
                    ["level": $0.level, "text": $0.text, "source": $0.source as Any] as [String: Any]
                },
            ]
        case .state(let state):
            // Encoded through the Codable type rather than rebuilt as a
            // dictionary, so the JSON cannot drift from the struct.
            if let data = try? JSONEncoder().encode(state),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            {
                dict = ["ok": true, "state": object]
            } else {
                dict = ["ok": false, "error": "Failed to encode page state"]
            }
        case .rawJSON(let json):
            return json
        case .plain(let text):
            dict = ["ok": true, "text": text]
        case .error(let message):
            dict = ["ok": false, "error": message]
        }
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: dict, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{\"ok\":false,\"error\":\"Failed to serialize JSON\"}"
        }
        return string
    }

    func formatError(_ payload: ErrorPayload) -> String {
        var error: [String: Any] = [
            "code": payload.code,
            "message": payload.message,
        ]
        if let url = payload.url { error["url"] = url }
        if let candidates = payload.candidates { error["candidates"] = candidates }

        let dict: [String: Any] = ["ok": false, "error": error]
        guard
            let data = try? JSONSerialization.data(
                withJSONObject: dict, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return "{\"ok\":false,\"error\":{\"code\":\"INTERNAL\"}}"
        }
        return string
    }
}

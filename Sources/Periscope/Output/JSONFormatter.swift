import Foundation

struct JSONFormatter: OutputFormatting {
    func format(_ result: CommandResult) -> String {
        let dict: [String: Any]
        switch result {
        case .navigate(let title, let url):
            dict = ["ok": true, "title": title as Any, "url": url]
        case .extract(let content):
            dict = ["ok": true, "content": content]
        case .html(let content):
            dict = ["ok": true, "html": content]
        case .links(let items):
            dict = ["ok": true, "links": items.map { ["text": $0.text, "url": $0.url] }]
        case .elements(let items):
            dict = ["ok": true, "elements": items.map {
                ["index": $0.index, "tag": $0.tag, "id": $0.id as Any,
                 "classes": $0.classes, "text": $0.text] as [String: Any]
            }]
        case .jsResult(let value):
            dict = ["ok": true, "value": value as Any]
        case .screenshot(let path):
            dict = ["ok": true, "path": path]
        case .cookies(let items):
            dict = ["ok": true, "cookies": items.map {
                ["name": $0.name, "value": $0.value, "domain": $0.domain]
            }]
        case .sessionList(let names):
            dict = ["ok": true, "sessions": names]
        case .history(let items):
            dict = ["ok": true, "history": items.map {
                ["title": $0.title as Any, "url": $0.url,
                 "current": $0.isCurrent] as [String: Any]
            }]
        case .plain(let text):
            dict = ["ok": true, "text": text]
        case .error(let message):
            dict = ["ok": false, "error": message]
        }
        guard let data = try? JSONSerialization.data(
                withJSONObject: dict, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
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

        let dict: [String: Any] = ["ok": false, "error": error]
        guard let data = try? JSONSerialization.data(
                withJSONObject: dict, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":{\"code\":\"INTERNAL\"}}"
        }
        return string
    }
}

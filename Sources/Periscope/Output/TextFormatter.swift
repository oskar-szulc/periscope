import Foundation

struct TextFormatter: OutputFormatting {
    func format(_ result: CommandResult) -> String {
        switch result {
        case .navigate(let title, let url):
            return "Navigated to: \(title ?? "(untitled)")\nURL: \(url)"
        case .extract(let content):
            return content
        case .html(let content):
            return content
        case .links(let items):
            return items.map { "- [\($0.text)](\($0.url))" }.joined(separator: "\n")
        case .elements(let items):
            return items.map { item in
                var desc = "\(item.index). <\(item.tag)"
                if let id = item.id { desc += " id=\"\(id)\"" }
                if !item.classes.isEmpty { desc += " class=\"\(item.classes.joined(separator: " "))\"" }
                desc += "> \"\(item.text)\""
                return desc
            }.joined(separator: "\n")
        case .jsResult(let value):
            return value ?? "(undefined)"
        case .screenshot(let path):
            return "Screenshot saved to \(path)"
        case .cookies(let items):
            return items.map { "\($0.name)=\($0.value) (domain: \($0.domain))" }.joined(separator: "\n")
        case .sessionList(let names):
            return names.isEmpty ? "No sessions found." : names.joined(separator: "\n")
        case .history(let items):
            return items.map { item in
                let marker = item.isCurrent ? " <- current" : ""
                return "- [\(item.title ?? "(untitled)")](\(item.url))\(marker)"
            }.joined(separator: "\n")
        case .plain(let text):
            return text
        case .error(let message):
            return "Error: \(message)"
        }
    }

    func formatError(_ payload: ErrorPayload) -> String {
        "Error: " + payload.message
    }
}

import Foundation

struct LinkItem: Sendable {
    let text: String
    let url: String
}

struct ElementItem: Sendable {
    let index: Int
    let tag: String
    let id: String?
    let classes: [String]
    let text: String
}

struct CookieItem: Sendable {
    let name: String
    let value: String
    let domain: String
}

struct HistoryItem: Sendable {
    let title: String?
    let url: String
    let isCurrent: Bool
}

enum CommandResult: Sendable {
    case navigate(title: String?, url: String)
    case extract(content: String)
    case html(content: String)
    case links([LinkItem])
    case elements([ElementItem])
    case jsResult(value: String?)
    case screenshot(path: String)
    case cookies([CookieItem])
    case sessionList([String])
    case history(items: [HistoryItem])
    case plain(String)
    case error(String)
}

protocol OutputFormatting: Sendable {
    func format(_ result: CommandResult) -> String
}

func makeFormatter(json: Bool) -> OutputFormatting {
    json ? JSONFormatter() : TextFormatter()
}

import Foundation

struct LinkItem: Sendable, Codable {
    let text: String
    let url: String
}

struct ElementItem: Sendable, Codable {
    let index: Int
    let tag: String
    let id: String?
    let classes: [String]
    let text: String
}

struct CookieItem: Sendable, Codable {
    let name: String
    let value: String
    let domain: String
}

struct HistoryItem: Sendable, Codable {
    let title: String?
    let url: String
    let isCurrent: Bool
}

enum CommandResult: Sendable, Codable {
    /// `status` is the main-frame HTTP status, nil for non-HTTP loads.
    /// `textChars` is the length of the settled page's visible text: a 404
    /// shell or an empty SPA frame is obvious from a small number.
    case navigate(title: String?, url: String, status: Int?, textChars: Int)
    case extract(content: String)
    case html(content: String)
    case links([LinkItem])
    case elements([ElementItem])
    case jsResult(value: String?)
    case screenshot(path: String)
    case cookies([CookieItem])
    case sessionList([String])
    case history(items: [HistoryItem])
    case state(PageStateData)
    case plain(String)
    case error(String)
}

protocol OutputFormatting: Sendable {
    func format(_ result: CommandResult) -> String
    /// Failures carry a stable machine-readable code, so a caller can branch on
    /// what went wrong instead of pattern-matching an English sentence.
    func formatError(_ payload: ErrorPayload) -> String
}

func makeFormatter(json: Bool) -> OutputFormatting {
    json ? JSONFormatter() : TextFormatter()
}

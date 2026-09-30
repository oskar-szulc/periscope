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

struct RequestItem: Sendable, Codable {
    let method: String
    let url: String
    /// nil while pending, or if the request failed before a response.
    let status: Int?
    /// "document", "fetch" or "xhr".
    let kind: String
    let durationMs: Int?
    /// Set when the request failed (network error, CORS, aborted). A nil status
    /// with an error is a failure; a nil status without one is still in flight.
    let error: String?
}

struct ConsoleItem: Sendable, Codable {
    let level: String
    let text: String
    let source: String?
}

struct HistoryItem: Sendable, Codable {
    let title: String?
    let url: String
    let isCurrent: Bool
}

enum CommandResult: Sendable, Codable {
    /// `status` is the main-frame HTTP status, nil for non-HTTP loads.
    /// `textChars` is the length of the settled page's visible text: a 404
    /// shell or an empty SPA frame is obvious from a small number. `htmlChars`
    /// says what `html` would cost before anyone asks for it.
    case navigate(title: String?, url: String, status: Int?, textChars: Int, htmlChars: Int)
    case extract(content: String)
    case html(content: String)
    case links([LinkItem])
    case elements([ElementItem])
    case jsResult(value: String?)
    case screenshot(path: String)
    case cookies([CookieItem])
    case sessionList([String])
    case history(items: [HistoryItem])
    case requests([RequestItem])
    case console([ConsoleItem])
    case state(PageStateData)
    case plain(String)
    /// A string that is already JSON: printed verbatim in both text and --json
    /// modes, so `extract` output is not wrapped or double-encoded.
    case rawJSON(String)
}

protocol OutputFormatting: Sendable {
    func format(_ result: CommandResult) -> String
    /// Failures carry a stable machine-readable code, so a caller can branch on
    /// what went wrong instead of pattern-matching an English sentence.
    func formatError(_ payload: ErrorPayload) -> String
}

func makeFormatter(json: Bool, fields: String? = nil) -> OutputFormatting {
    json ? JSONFormatter(fields: fields.map(Extraction.fieldList)) : TextFormatter()
}

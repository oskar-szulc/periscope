import Foundation

/// `login --until`: when the person at the window is done.
///
///   selector:<css>   an element matching <css> exists
///   url:<text>       the URL contains <text>
///   title:<text>     the title contains <text>
///
/// A `!` before the colon inverts it (`title!:Just a moment` waits for a
/// challenge page to go away), so no knowledge of the target page's markup
/// is needed.
struct UntilCondition: Equatable, CustomStringConvertible {
    enum Kind: String { case selector, url, title }
    var kind: Kind
    var negated: Bool
    var value: String

    static func parse(_ raw: String) throws -> UntilCondition {
        guard let colon = raw.firstIndex(of: ":") else { throw invalid(raw) }
        var name = String(raw[..<colon])
        let negated = name.hasSuffix("!")
        if negated { name.removeLast() }
        let value = String(raw[raw.index(after: colon)...])
        guard let kind = Kind(rawValue: name), !value.isEmpty else { throw invalid(raw) }
        return UntilCondition(kind: kind, negated: negated, value: value)
    }

    /// Whether the condition holds for a page. `matches` is the selector's
    /// answer; it is only consulted for `.selector`.
    func holds(url: String, title: String, matches: Bool) -> Bool {
        let hit: Bool
        switch kind {
        case .selector: hit = matches
        case .url: hit = url.contains(value)
        case .title: hit = title.localizedCaseInsensitiveContains(value)
        }
        return hit != negated
    }

    var description: String { "\(kind.rawValue)\(negated ? "!" : ""):\(value)" }

    private static func invalid(_ raw: String) -> PeriscopeError {
        .argumentError(
            reason:
                "Invalid --until '\(raw)'. Use selector:<css>, url:<text> or title:<text>, with ! before the colon to invert (title!:Just a moment)"
        )
    }
}

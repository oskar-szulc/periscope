import Foundation

/// Narrows a page summary to what the agent asked about.
///
/// `state` on a link-dense page returned 80 actions and 14k characters to answer
/// "what is the search box's selector". The cap keeps the default answer short
/// and says how much was left out; `match` gets straight to the one that matters.
enum StateFilter {
    static let defaultLimit = 25

    static func apply(_ state: PageStateData, match: String?, limit: Int?) throws -> PageStateData {
        var out = state
        if let match {
            let matches = try RegexFilter.matcher(match)
            out.elements = state.elements.filter { element in
                [element.selector, element.label, element.text, element.href, element.tag]
                    .compactMap { $0 }
                    .contains { matches($0) }
            }
        }
        if let limit, out.elements.count > limit {
            out.omitted = out.elements.count - limit
            out.elements = Array(out.elements.prefix(limit))
        } else {
            out.omitted = nil
        }
        return out
    }
}

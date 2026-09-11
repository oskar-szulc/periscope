import Foundation

enum LinkFilter {
    /// Keep the links whose URL matches `pattern` (ICU regex, unanchored).
    static func apply(pattern: String, to links: [LinkItem]) throws -> [LinkItem] {
        let matches = try RegexFilter.matcher(pattern)
        return links.filter { matches($0.url) }
    }
}

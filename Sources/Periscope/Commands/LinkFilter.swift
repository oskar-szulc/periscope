import Foundation

enum LinkFilter {
    /// Keep the links whose URL contains a match for `pattern` (ICU regex,
    /// unanchored). An invalid pattern is the caller's mistake, not a page fault.
    static func apply(pattern: String, to links: [LinkItem]) throws -> [LinkItem] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw PeriscopeError.argumentError(reason: "Invalid --match regex: \(pattern)")
        }
        return links.filter { link in
            let range = NSRange(link.url.startIndex..., in: link.url)
            return regex.firstMatch(in: link.url, range: range) != nil
        }
    }
}

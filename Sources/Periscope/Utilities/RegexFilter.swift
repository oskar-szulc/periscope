import Foundation

/// The `--match` idiom, in one place: compile a pattern into an unanchored
/// predicate, or fail with an argument error. Shared by `links`, `state` and
/// `requests` so anchoring, case-folding and the error wording cannot drift.
enum RegexFilter {
    static func matcher(_ pattern: String) throws -> (String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw PeriscopeError.argumentError(reason: "Invalid --match regex: \(pattern)")
        }
        return { s in
            regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
    }
}

import Foundation

enum PeriscopeError: Error, CustomStringConvertible {
    case elementNotFound(selector: String)
    /// `candidates` are one-line descriptions with a unique selector each, so
    /// the next attempt can be exact instead of a guess.
    case multipleElementsFound(selector: String, count: Int, candidates: [String])
    /// Found, but hidden or disabled for the whole actionability wait.
    case notActionable(selector: String, reason: String)
    case navigationFailed(url: String, reason: String)
    case timeout(seconds: Int)
    case sessionError(reason: String)
    case javaScriptError(reason: String)
    case argumentError(reason: String)
    case screenshotFailed(reason: String)
    /// The page loaded, but it is a bot challenge, not the content asked for.
    case blocked(kind: BlockKind, url: String)

    var exitCode: Int32 {
        switch self {
        case .elementNotFound, .multipleElementsFound, .notActionable, .javaScriptError, .screenshotFailed:
            return 1
        case .navigationFailed, .timeout:
            return 2
        case .sessionError:
            return 3
        case .argumentError:
            return 4
        case .blocked:
            return 5
        }
    }

    var description: String {
        switch self {
        case .elementNotFound(let selector):
            return "Element not found: \(selector)"
        case .multipleElementsFound(let selector, let count, let candidates):
            var text = "Selector '\(selector)' matched \(count) elements. Pick one, or pass --first to act on the first:"
            for candidate in candidates { text += "\n  \(candidate)" }
            if count > candidates.count { text += "\n  ... and \(count - candidates.count) more" }
            return text
        case .notActionable(let selector, let reason):
            return "Element \(selector) is not actionable: \(reason)"
        case .navigationFailed(let url, let reason):
            return url.isEmpty
                ? "Navigation failed: \(reason)"
                : "Navigation to \(url) failed: \(reason)"
        case .timeout(let seconds):
            return "Operation timed out after \(seconds)s"
        case .sessionError(let reason):
            return "Session error: \(reason)"
        case .javaScriptError(let reason):
            return "JavaScript error: \(reason)"
        case .argumentError(let reason):
            return "Argument error: \(reason)"
        case .screenshotFailed(let reason):
            return "Screenshot failed: \(reason)"
        case .blocked(let kind, let url):
            return "Blocked by \(kind.rawValue) at \(url)"
        }
    }
}

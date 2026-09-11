import Foundation

enum PeriscopeError: Error, CustomStringConvertible {
    case elementNotFound(selector: String)
    case multipleElementsFound(selector: String, count: Int)
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
        case .elementNotFound, .multipleElementsFound, .javaScriptError, .screenshotFailed:
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
        case .multipleElementsFound(let selector, let count):
            return "Selector '\(selector)' matched \(count) elements (--strict mode requires exactly 1)"
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

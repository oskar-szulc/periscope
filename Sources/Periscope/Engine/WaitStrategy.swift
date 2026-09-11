import Foundation

enum WaitStrategy: Sendable, Equatable {
    /// Return as soon as the action itself is done.
    case none
    case load
    /// Wait until fetch/XHR traffic has been quiet for 500ms. `maxMs` caps the
    /// wait: pages with analytics beacons or long-polling never go quiet, and
    /// without a cap every one of them would run into `--timeout`.
    case fetchquiet(maxMs: Int?)
    case selector(String)
    case time(Int)  // milliseconds

    /// What `navigate` does when `--wait` is not given: settle SPA boards that
    /// render after `load`, but never hold an ordinary page for more than 5s.
    static let navigateDefault: WaitStrategy = .fetchquiet(maxMs: 5000)

    static func parse(_ string: String) -> WaitStrategy? {
        switch string {
        case "none": return WaitStrategy.none
        case "load": return .load
        case "fetchquiet": return .fetchquiet(maxMs: nil)
        default:
            if string.hasPrefix("fetchquiet:"),
               let ms = Int(string.dropFirst("fetchquiet:".count)) {
                return .fetchquiet(maxMs: ms)
            }
            if string.hasPrefix("selector:") {
                return .selector(String(string.dropFirst("selector:".count)))
            }
            if string.hasPrefix("time:"),
               let ms = Int(string.dropFirst("time:".count)) {
                return .time(ms)
            }
            return nil
        }
    }
}

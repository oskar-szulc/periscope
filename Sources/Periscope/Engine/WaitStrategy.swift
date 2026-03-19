import Foundation

enum WaitStrategy: Sendable {
    case load
    case fetchquiet
    case selector(String)
    case time(Int)  // milliseconds

    static func parse(_ string: String) -> WaitStrategy? {
        switch string {
        case "load": return .load
        case "fetchquiet": return .fetchquiet
        default:
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

import Foundation
import WebKit

/// Records the HTTP status of the main-frame response for the navigation in
/// flight.
///
/// `WebPage.NavigationResponse` does not say which frame a response belongs
/// to, but ordering does: subframes cannot start loading before the main
/// frame has committed, so the first response after `reset()` is the main
/// frame's. Server redirects are followed inside WebKit and never reach the
/// decider, so that first response is also the final one.
@MainActor
final class NavigationObserver: WebPage.NavigationDeciding {
    private(set) var statusCode: Int?
    private var recorded = false

    func reset() {
        statusCode = nil
        recorded = false
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        if !recorded {
            recorded = true
            statusCode = (response.response as? HTTPURLResponse)?.statusCode
        }
        return .allow
    }
}

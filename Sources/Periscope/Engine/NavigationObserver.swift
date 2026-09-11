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
final class ResponseRecorder {
    private(set) var statusCode: Int?
    private var recorded = false

    func reset() {
        statusCode = nil
        recorded = false
    }

    func record(_ response: URLResponse) {
        guard !recorded else { return }
        recorded = true
        statusCode = (response as? HTTPURLResponse)?.statusCode
    }
}

struct NavigationObserver: WebPage.NavigationDeciding {
    let recorder: ResponseRecorder

    mutating func decidePolicy(
        for response: WebPage.NavigationResponse
    ) async -> WKNavigationResponsePolicy {
        recorder.record(response.response)
        return .allow
    }
}

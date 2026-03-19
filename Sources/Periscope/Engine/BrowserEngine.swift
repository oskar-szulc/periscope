import Foundation
import WebKit

@MainActor
final class BrowserEngine {
    let windowController: HiddenWindowController
    private var webView: WKWebView { windowController.webView }

    init(viewportWidth: Int = 1920, viewportHeight: Int = 1080) {
        self.windowController = HiddenWindowController(
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
    }

    // MARK: - Navigation

    func navigate(to url: URL) async throws -> (title: String?, url: String) {
        webView.load(URLRequest(url: url))
        try await waitForLoad()
        let title = try await webView.evaluateJavaScript("document.title") as? String
        return (title, webView.url?.absoluteString ?? url.absoluteString)
    }

    func goBack() async throws -> (title: String?, url: String) {
        guard webView.canGoBack else {
            throw PeriscopeError.navigationFailed(url: "", reason: "No back history")
        }
        webView.goBack()
        try await waitForLoad()
        let title = try await webView.evaluateJavaScript("document.title") as? String
        return (title, webView.url?.absoluteString ?? "")
    }

    func goForward() async throws -> (title: String?, url: String) {
        guard webView.canGoForward else {
            throw PeriscopeError.navigationFailed(url: "", reason: "No forward history")
        }
        webView.goForward()
        try await waitForLoad()
        let title = try await webView.evaluateJavaScript("document.title") as? String
        return (title, webView.url?.absoluteString ?? "")
    }

    func reload() async throws -> (title: String?, url: String) {
        webView.reload()
        try await waitForLoad()
        let title = try await webView.evaluateJavaScript("document.title") as? String
        return (title, webView.url?.absoluteString ?? "")
    }

    var currentURL: String? { webView.url?.absoluteString }
    var currentTitle: String? { webView.title }

    // MARK: - JavaScript

    func runJavaScript(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    // MARK: - Wait

    func waitForLoad() async throws {
        // Poll isLoading
        while webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func close() {
        windowController.close()
    }
}

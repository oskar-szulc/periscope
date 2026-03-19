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

    // MARK: - History

    func getHistory() async throws -> [HistoryItem] {
        var items: [HistoryItem] = []
        let list = webView.backForwardList
        for item in list.backList {
            items.append(HistoryItem(title: item.title, url: item.url.absoluteString, isCurrent: false))
        }
        if let current = list.currentItem {
            items.append(HistoryItem(title: current.title, url: current.url.absoluteString, isCurrent: true))
        }
        for item in list.forwardList {
            items.append(HistoryItem(title: item.title, url: item.url.absoluteString, isCurrent: false))
        }
        return items
    }

    // MARK: - Wait

    func waitForLoad() async throws {
        // Poll isLoading
        while webView.isLoading {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func installFetchMonitor() async throws {
        _ = try await runJavaScript(FetchQuietMonitor.installScript)
    }

    func waitFor(_ strategy: WaitStrategy) async throws {
        switch strategy {
        case .load:
            try await waitForLoad()
        case .fetchquiet:
            try await installFetchMonitor()
            while true {
                while true {
                    let quiet = try await runJavaScript(FetchQuietMonitor.checkScript) as? Bool ?? true
                    if quiet && !webView.isLoading { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                try await Task.sleep(for: .milliseconds(500))
                let stillQuiet = try await runJavaScript(FetchQuietMonitor.checkScript) as? Bool ?? true
                if stillQuiet && !webView.isLoading { break }
            }
        case .selector(let css):
            while true {
                let exists = try await runJavaScript(ElementResolver.existsScript(selector: css)) as? Bool ?? false
                if exists { break }
                try await Task.sleep(for: .milliseconds(100))
            }
        case .time(let ms):
            try await Task.sleep(for: .milliseconds(ms))
        }
    }

    func resolveElement(selector: String, strict: Bool) async throws {
        let count = try await runJavaScript(ElementResolver.countScript(selector: selector)) as? Int ?? 0
        if count == 0 {
            throw PeriscopeError.elementNotFound(selector: selector)
        }
        if strict && count > 1 {
            throw PeriscopeError.multipleElementsFound(selector: selector, count: count)
        }
    }

    func close() {
        windowController.close()
    }
}

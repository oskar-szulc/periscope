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

    // MARK: - Interaction

    func click(selector: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        _ = try await runJavaScript(ElementResolver.clickScript(selector: selector))
    }

    func fill(selector: String, value: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        _ = try await runJavaScript(ElementResolver.fillScript(selector: selector, value: value))
    }

    func selectOption(selector: String, value: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        _ = try await runJavaScript(ElementResolver.selectScript(selector: selector, value: value))
    }

    func setChecked(selector: String, checked: Bool, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        _ = try await runJavaScript(ElementResolver.checkScript(selector: selector, checked: checked))
    }

    func submit(selector: String?) async throws {
        if let selector { try await resolveElement(selector: selector, strict: false) }
        _ = try await runJavaScript(ElementResolver.submitScript(selector: selector))
    }

    func scroll(target: String) async throws {
        if !["up", "down", "top", "bottom"].contains(target) {
            try await resolveElement(selector: target, strict: false)
        }
        _ = try await runJavaScript(ElementResolver.scrollScript(target: target))
    }

    func hover(selector: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        _ = try await runJavaScript(ElementResolver.hoverScript(selector: selector))
    }

    // MARK: - Extraction

    func extractText(selector: String?, raw: Bool) async throws -> String {
        let js: String
        if let selector {
            js = """
            (function() {
                var el = document.querySelector(\(ElementResolver.jsString(selector)));
                return el ? el.innerHTML : null;
            })();
            """
        } else {
            js = """
            (function() {
                var el = document.querySelector('main')
                      || document.querySelector('article')
                      || document.body;
                return el ? el.innerHTML : '';
            })();
            """
        }
        guard let html = try await runJavaScript(js) as? String else {
            throw PeriscopeError.elementNotFound(selector: selector ?? "body")
        }
        return raw ? html : HTMLToMarkdown().convert(html)
    }

    func extractHTML(selector: String?) async throws -> String {
        let js: String
        if let selector {
            js = """
            (function() {
                var el = document.querySelector(\(ElementResolver.jsString(selector)));
                return el ? el.outerHTML : null;
            })();
            """
        } else {
            js = "document.documentElement.outerHTML"
        }
        guard let html = try await runJavaScript(js) as? String else {
            throw PeriscopeError.elementNotFound(selector: selector ?? "html")
        }
        return html
    }

    func extractAttribute(selector: String, attribute: String) async throws -> String {
        let js = """
        (function() {
            var el = document.querySelector(\(ElementResolver.jsString(selector)));
            return el ? el.getAttribute(\(ElementResolver.jsString(attribute))) : null;
        })();
        """
        guard let value = try await runJavaScript(js) as? String else {
            throw PeriscopeError.elementNotFound(selector: selector)
        }
        return value
    }

    func extractLinks() async throws -> [LinkItem] {
        let js = """
        Array.from(document.querySelectorAll('a[href]')).map(function(a) {
            return { text: a.textContent.trim(), url: a.getAttribute('href') };
        })
        """
        guard let results = try await runJavaScript(js) as? [[String: Any]] else {
            return []
        }
        return results.map { LinkItem(text: $0["text"] as? String ?? "", url: $0["url"] as? String ?? "") }
    }

    func extractTable(selector: String) async throws -> String {
        let js = """
        (function() {
            var table = document.querySelector(\(ElementResolver.jsString(selector)));
            if (!table) return null;
            return Array.from(table.querySelectorAll('tr')).map(function(row) {
                return Array.from(row.querySelectorAll('td, th'))
                    .map(function(cell) { return cell.textContent.trim(); });
            });
        })();
        """
        guard let rows = try await runJavaScript(js) as? [[String]] else {
            throw PeriscopeError.elementNotFound(selector: selector)
        }
        guard !rows.isEmpty else { return "" }
        var lines: [String] = []
        lines.append("| " + rows[0].joined(separator: " | ") + " |")
        lines.append("| " + rows[0].map { _ in "---" }.joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append("| " + row.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n")
    }
}

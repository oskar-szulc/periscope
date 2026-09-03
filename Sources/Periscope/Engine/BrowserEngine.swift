import Foundation
import WebKit

@MainActor
final class BrowserEngine {
    let windowController: HiddenWindowController
    private var page: WebPage { windowController.page }
    var verbose: Bool = false

    init(viewportWidth: Int = 1920, viewportHeight: Int = 1080) {
        self.windowController = HiddenWindowController(
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
    }

    // MARK: - Navigation

    /// Navigate to a URL using the WebPage AsyncSequence navigation API.
    /// Awaits the `.finished` event instead of polling `isLoading`.
    func navigate(to url: URL) async throws -> (title: String?, url: String) {
        let events = page.load(URLRequest(url: url))
        try await awaitNavigation(events, target: url.absoluteString)
        let title = await resolveTitle()
        return (title, page.url?.absoluteString ?? url.absoluteString)
    }

    func goBack() async throws -> (title: String?, url: String) {
        let list = page.backForwardList
        guard let backItem = list.backList.last else {
            throw PeriscopeError.navigationFailed(
                url: page.url?.absoluteString ?? "", reason: "No back history")
        }
        let events = page.load(backItem)
        try await awaitNavigation(events, target: backItem.url.absoluteString)
        let title = await resolveTitle()
        return (title, page.url?.absoluteString ?? "")
    }

    func goForward() async throws -> (title: String?, url: String) {
        let list = page.backForwardList
        guard let forwardItem = list.forwardList.first else {
            throw PeriscopeError.navigationFailed(
                url: page.url?.absoluteString ?? "", reason: "No forward history")
        }
        let events = page.load(forwardItem)
        try await awaitNavigation(events, target: forwardItem.url.absoluteString)
        let title = await resolveTitle()
        return (title, page.url?.absoluteString ?? "")
    }

    func reload() async throws -> (title: String?, url: String) {
        let events = page.reload()
        try await awaitNavigation(events, target: page.url?.absoluteString ?? "")
        let title = await resolveTitle()
        return (title, page.url?.absoluteString ?? "")
    }

    var currentURL: String? { page.url?.absoluteString }
    var currentTitle: String? { page.title.isEmpty ? nil : page.title }

    /// Resolve the page title, using JS as fallback since the observable
    /// `page.title` may not have updated yet after navigation completes.
    private func resolveTitle() async -> String? {
        if !page.title.isEmpty { return page.title }
        // page.title hasn't propagated yet — get it from the DOM directly
        let jsTitle = try? await runJavaScript("document.title") as? String
        if let jsTitle, !jsTitle.isEmpty { return jsTitle }
        return nil
    }

    // MARK: - Navigation Event Handling

    /// Await a navigation's AsyncSequence until `.finished`, logging events if verbose.
    /// If the sequence throws (e.g. a redirect cancels the provisional navigation),
    /// fall back to polling until the replacement navigation completes.
    ///
    /// - Parameter target: the URL being navigated to. A failed *provisional* navigation
    ///   never commits, so `page.url` is still nil at that point — without this the error
    ///   would report an empty URL.
    private func awaitNavigation(
        _ events: some AsyncSequence<WebPage.NavigationEvent, any Error>,
        target: String
    ) async throws {
        do {
            for try await event in events {
                if verbose {
                    FileHandle.standardError.write(Data("nav: \(event)\n".utf8))
                }
                if event == .finished { return }
            }
        } catch let navError as WebPage.NavigationError {
            switch navError {
            case .failedProvisionalNavigation(let underlying):
                throw PeriscopeError.navigationFailed(
                    url: failedURL(underlying) ?? target,
                    reason: Self.describe(underlying))
            case .pageClosed:
                throw PeriscopeError.navigationFailed(url: target, reason: "Page was closed")
            case .webContentProcessTerminated:
                throw PeriscopeError.navigationFailed(
                    url: target, reason: "Web content process terminated")
            case .invalidURL:
                throw PeriscopeError.navigationFailed(url: target, reason: "Invalid URL")
            @unknown default:
                throw PeriscopeError.navigationFailed(url: target, reason: "\(navError)")
            }
        } catch {
            // Non-navigation error (e.g. cancellation). Fall back to polling.
            if verbose {
                FileHandle.standardError.write(Data("nav: unexpected error: \(error), falling back\n".utf8))
            }
            while page.isLoading {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// The URL URLSession reports as failing, which differs from the requested URL
    /// when the failure happened after a redirect.
    private func failedURL(_ error: any Error) -> String? {
        let ns = error as NSError
        return (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
    }

    /// Append the underlying error domain/code to Apple's terse message, so
    /// "Could not connect to the server." becomes diagnosable.
    static func describe(_ error: any Error) -> String {
        let ns = error as NSError
        let message = ns.localizedDescription
        switch ns.domain {
        case NSURLErrorDomain:
            return "\(message) (NSURLError \(ns.code))"
        case let domain where domain == kCFErrorDomainCFNetwork as String:
            return "\(message) (CFNetwork \(ns.code))"
        default:
            return "\(message) (\(ns.domain) \(ns.code))"
        }
    }

    // MARK: - JavaScript

    /// Execute JavaScript on the current page.
    /// WebPage.callJavaScript treats the script as a function body,
    /// so we prepend `return` to get the expression result back.
    func runJavaScript(_ script: String) async throws -> Any? {
        try await page.callJavaScript("return \(script)")
    }

    /// Execute JavaScript without expecting a return value (side-effects only).
    func runJavaScriptVoid(_ script: String) async throws {
        _ = try await page.callJavaScript(script)
    }

    // MARK: - History

    func getHistory() async throws -> [HistoryItem] {
        var items: [HistoryItem] = []
        let list = page.backForwardList
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
        // Use the navigations stream to wait for the current load to finish,
        // falling back to polling if no navigation is in progress.
        if page.isLoading {
            for try await event in page.navigations {
                if verbose {
                    FileHandle.standardError.write(Data("nav: \(event)\n".utf8))
                }
                if event == .finished { break }
            }
        }
    }

    func installFetchMonitor() async throws {
        try await runJavaScriptVoid(FetchQuietMonitor.installScript)
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
                    if quiet && !page.isLoading { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                try await Task.sleep(for: .milliseconds(500))
                let stillQuiet = try await runJavaScript(FetchQuietMonitor.checkScript) as? Bool ?? true
                if stillQuiet && !page.isLoading { break }
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

    func showWindow() {
        windowController.showWindow()
    }

    func hideWindow() {
        windowController.hideWindow()
    }

    /// Wait for the URL to change away from `initialPath`, or for an explicit condition.
    func waitForLoginCompletion(initialURL: URL, until: String?) async throws {
        let initialPath = initialURL.path

        while true {
            if let until {
                if until.hasPrefix("selector:") {
                    let css = String(until.dropFirst("selector:".count))
                    let exists = try await runJavaScript(ElementResolver.existsScript(selector: css)) as? Bool ?? false
                    if exists { break }
                } else if until.hasPrefix("url:") {
                    let pattern = String(until.dropFirst("url:".count))
                    if let currentURL = page.url?.absoluteString, currentURL.contains(pattern) { break }
                }
            } else {
                if let currentURL = page.url {
                    let currentPath = currentURL.path
                    if currentPath != initialPath && !page.isLoading {
                        try await Task.sleep(for: .milliseconds(1000))
                        break
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    func close() {
        windowController.close()
    }

    // MARK: - Screenshot

    /// Take a screenshot using WebPage.exported(as:) for native image capture.
    func takeScreenshot(full: Bool) async throws -> Data {
        let config: WebPage.ExportedContentConfiguration
        if full {
            config = .image(region: .contents)
        } else {
            config = .image()
        }
        return try await page.exported(as: config)
    }

    /// Export the current page as a PDF.
    func exportPDF() async throws -> Data {
        try await page.exported(as: .pdf())
    }

    // MARK: - Interaction

    func click(selector: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        try await runJavaScriptVoid(ElementResolver.clickScript(selector: selector))
    }

    func fill(selector: String, value: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        try await runJavaScriptVoid(ElementResolver.fillScript(selector: selector, value: value))
    }

    func selectOption(selector: String, value: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        try await runJavaScriptVoid(ElementResolver.selectScript(selector: selector, value: value))
    }

    func setChecked(selector: String, checked: Bool, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        try await runJavaScriptVoid(ElementResolver.checkScript(selector: selector, checked: checked))
    }

    func submit(selector: String?) async throws {
        if let selector { try await resolveElement(selector: selector, strict: false) }
        try await runJavaScriptVoid(ElementResolver.submitScript(selector: selector))
    }

    func scroll(target: String) async throws {
        if !["up", "down", "top", "bottom"].contains(target) {
            try await resolveElement(selector: target, strict: false)
        }
        try await runJavaScriptVoid(ElementResolver.scrollScript(target: target))
    }

    func hover(selector: String, strict: Bool) async throws {
        try await resolveElement(selector: selector, strict: strict)
        try await runJavaScriptVoid(ElementResolver.hoverScript(selector: selector))
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

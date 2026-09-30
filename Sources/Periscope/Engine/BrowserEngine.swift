import Foundation
import WebKit

@MainActor
final class BrowserEngine {
    let windowController: HiddenWindowController
    private var page: WebPage { windowController.page }

    /// `--user-agent`. Sticks for the life of the page once set, so a live
    /// session keeps one identity (Cloudflare binds its clearance cookie to it).
    func setUserAgent(_ userAgent: String?) {
        if let userAgent { page.customUserAgent = userAgent }
    }
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
    func navigate(to url: URL) async throws -> String {
        windowController.responseRecorder.reset()
        let events = page.load(URLRequest(url: url))
        try await awaitNavigation(events, target: url.absoluteString)
        return page.url?.absoluteString ?? url.absoluteString
    }

    func goBack() async throws -> String {
        let list = page.backForwardList
        guard let backItem = list.backList.last else {
            throw PeriscopeError.navigationFailed(
                url: page.url?.absoluteString ?? "", reason: "No back history")
        }
        windowController.responseRecorder.reset()
        let events = page.load(backItem)
        try await awaitNavigation(events, target: backItem.url.absoluteString)
        return page.url?.absoluteString ?? ""
    }

    func goForward() async throws -> String {
        let list = page.backForwardList
        guard let forwardItem = list.forwardList.first else {
            throw PeriscopeError.navigationFailed(
                url: page.url?.absoluteString ?? "", reason: "No forward history")
        }
        windowController.responseRecorder.reset()
        let events = page.load(forwardItem)
        try await awaitNavigation(events, target: forwardItem.url.absoluteString)
        return page.url?.absoluteString ?? ""
    }

    func reload() async throws -> String {
        windowController.responseRecorder.reset()
        let events = page.reload()
        try await awaitNavigation(events, target: page.url?.absoluteString ?? "")
        return page.url?.absoluteString ?? ""
    }

    var currentURL: String? { page.url?.absoluteString }
    var currentTitle: String? { page.title.isEmpty ? nil : page.title }

    /// Where the page is, for a timeout message: "the challenge never cleared"
    /// and "my selector was wrong" look identical without it.
    var locationDescription: String {
        "\(currentURL ?? "(no page)") \"\(currentTitle ?? "")\""
    }

    /// HTTP status of the main-frame response for the most recent navigation.
    var lastStatusCode: Int? { windowController.responseRecorder.statusCode }

    struct PageObservation {
        var title: String?
        var textChars: Int
        var blocked: BlockKind?
    }

    private struct PageProbe: Decodable {
        var url: String
        var title: String
        var textChars: Int
        var blockText: String
    }

    /// One look at the settled page — title, visible-text length, and whether it
    /// is a bot challenge — in a single round trip. Title, text and block markers
    /// are three facets of the same page, so reading them separately was three
    /// awaits to the web content process where one does.
    func observePage() async throws -> PageObservation {
        let script = """
        JSON.stringify({
            url: location.href,
            title: document.title || '',
            textChars: (document.body && document.body.innerText || '').replace(/\\s+/g, ' ').trim().length,
            blockText: (document.body && document.body.innerText || '').slice(0, 4000)
        })
        """
        guard let probe: PageProbe = try await runJavaScriptDecoded(script) else {
            return PageObservation(title: nil, textChars: 0, blocked: nil)
        }
        return PageObservation(
            title: probe.title.isEmpty ? nil : probe.title,
            textChars: probe.textChars,
            blocked: BlockDetector.classify(url: probe.url, title: probe.title, text: probe.blockText))
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

    /// Run a script that returns a JSON string and decode it, or nil on any
    /// failure (not a string, bad UTF-8, or a decode mismatch). One place for the
    /// `run → String → data → decode` ladder every diagnostics reader used.
    func runJavaScriptDecoded<T: Decodable>(_ script: String) async throws -> T? {
        guard let json = try await runJavaScript(script) as? String,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
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

    func waitFor(_ strategy: WaitStrategy) async throws {
        switch strategy {
        case .load:
            try await waitForLoad()
        case .none:
            return
        case .fetchquiet(let maxMs):
            // The monitor is injected at document start; no per-wait install.
            let deadline = maxMs.map { Date().addingTimeInterval(Double($0) / 1000) }
            func expired() -> Bool { deadline.map { Date() >= $0 } ?? false }
            while !expired() {
                while !expired() {
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

    private struct ElementProbe: Decodable {
        var count: Int
        var actionable: Bool
        var reason: String?
        var candidates: [String]
    }

    /// Wait for the target to exist, be visible and be enabled, up to
    /// `ElementResolver.actionabilityWaitMs`. Ambiguity fails immediately with
    /// the candidates listed; waiting would not make two elements into one.
    func resolveElement(selector: String, strict: Bool) async throws {
        let deadline = Date().addingTimeInterval(Double(ElementResolver.actionabilityWaitMs) / 1000)
        var last = ElementProbe(count: 0, actionable: false, reason: nil, candidates: [])
        while true {
            if let probe: ElementProbe = try await runJavaScriptDecoded(
                ElementResolver.probeScript(selector: selector)) {
                last = probe
            }
            if last.count > 0 {
                if strict && last.count > 1 {
                    throw PeriscopeError.multipleElementsFound(
                        selector: selector, count: last.count, candidates: last.candidates)
                }
                if last.actionable { return }
            }
            if Date() >= deadline { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if last.count == 0 { throw PeriscopeError.elementNotFound(selector: selector) }
        throw PeriscopeError.notActionable(selector: selector, reason: last.reason ?? "not visible")
    }

    func pressEnter(selector: String) async throws {
        try await runJavaScriptVoid(ElementResolver.pressEnterScript(selector: selector))
    }

    // MARK: - Cookie jar

    func allCookies() async -> [HTTPCookie] {
        await windowController.dataStore.httpCookieStore.allCookies()
    }

    func setCookies(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            await windowController.dataStore.httpCookieStore.setCookie(cookie)
        }
    }

    func deleteCookie(_ cookie: HTTPCookie) async {
        await windowController.dataStore.httpCookieStore.deleteCookie(cookie)
    }

    // MARK: - Diagnostics

    private struct RecordedRequest: Decodable {
        var method: String
        var url: String
        var kind: String
        var status: Int?
        var ms: Int?
        var error: String?
    }

    /// Let in-flight fetch/XHR resolve before a `requests` snapshot, so a request
    /// that is about to return 200 is not reported as "pending". Bounded, because
    /// a page with long-polling or a beacon never reaches zero in flight.
    func settleRequests(maxMs: Int) async throws {
        guard maxMs > 0 else { return }
        let deadline = Date().addingTimeInterval(Double(maxMs) / 1000)
        while Date() < deadline {
            let inflight = try await runJavaScript("window.__periscope_inflight || 0") as? Int ?? 0
            if inflight == 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The main document first, then everything the page's scripts fetched.
    func recordedRequests() async throws -> [RequestItem] {
        var items: [RequestItem] = []
        if let url = currentURL {
            items.append(RequestItem(method: "GET", url: url, status: lastStatusCode, kind: "document", durationMs: nil, error: nil))
        }
        if let recorded: [RecordedRequest] = try await runJavaScriptDecoded(
            FetchQuietMonitor.readRequestsScript) {
            items += recorded.map {
                RequestItem(method: $0.method, url: $0.url, status: $0.status,
                            kind: $0.kind, durationMs: $0.ms, error: $0.error)
            }
        }
        return items
    }

    func consoleMessages() async throws -> [ConsoleItem] {
        try await runJavaScriptDecoded(ConsoleMonitor.readScript) ?? []
    }

    func showWindow() {
        windowController.showWindow()
    }

    func hideWindow() {
        windowController.hideWindow()
    }

    /// Wait for the URL to change away from `initialPath`, or for an explicit condition.
    func waitForLoginCompletion(initialURL: URL, until: UntilCondition?) async throws {
        let initialPath = initialURL.path

        while true {
            if let until {
                // Mid-navigation the page may refuse JS; that is "not yet", not a failure.
                let matches = until.kind == .selector
                    ? (try? await runJavaScript(ElementResolver.existsScript(selector: until.value))) as? Bool ?? false
                    : false
                if until.holds(url: page.url?.absoluteString ?? "", title: page.title, matches: matches) { break }
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

    /// The page's readable text for extraction: `innerText` of the target (or
    /// main/article/body), block boundaries kept as newlines, runs of spaces
    /// collapsed. With no selector the page chrome (nav, header, footer, aside)
    /// is stripped; with an explicit selector only scripts/styles are, since the
    /// caller aimed at what they want.
    func readableContent(from selector: String?) async throws -> String {
        let rootExpr = selector.map { "document.querySelector(\(ElementResolver.jsString($0)))" }
            ?? PageSummarizer.mainContentExpr
        let extraStrip = selector == nil ? ", nav, header, footer, aside" : ""
        let js = """
        (function() {
            var root = \(rootExpr);
            if (!root) return null;
            var clone = root.cloneNode(true);
            clone.querySelectorAll('script, style, noscript, iframe, svg\(extraStrip)')
                .forEach(function(el) { el.remove(); });
            document.body.appendChild(clone);
            clone.style.position = 'absolute'; clone.style.left = '-99999px';
            var text = clone.innerText || clone.textContent || '';
            clone.remove();
            return text.split('\\n')
                .map(function(l) { return l.replace(/[ \\t]+/g, ' ').trim(); })
                .filter(function(l) { return l.length; })
                .join('\\n');
        })()
        """
        guard let text = try await runJavaScript(js) as? String else {
            throw PeriscopeError.elementNotFound(selector: selector ?? "body")
        }
        return text
    }

    /// `extract`'s deterministic result (see `PageRecords`). When no records
    /// turn up, the readable text rides along, so an article or a detail page
    /// still comes back with its content.
    func pageRecords(from: String?, items: String?) async throws -> [String: Any] {
        guard var records = try await runJavaScript(PageRecords.script(from: from, items: items))
                as? [String: Any] else {
            throw PeriscopeError.elementNotFound(selector: from ?? "body")
        }
        if (records["items"] as? [Any])?.isEmpty ?? true {
            if let items { throw PeriscopeError.elementNotFound(selector: items) }
            records["text"] = String(try await readableContent(from: from).prefix(Extraction.fallbackCap))
        }
        return records
    }

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
                var el = \(PageSummarizer.mainContentExpr);
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
            return { text: a.textContent.trim(), url: a.href };
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

import Foundation

/// Counts in-flight fetch/XHR traffic for the `fetchquiet` wait, and keeps a
/// log of every request for `periscope requests`. Installed at document start.
enum FetchQuietMonitor {
    static let installScript = """
    (function() {
        if (window.__periscope_installed) return;
        window.__periscope_installed = true;
        window.__periscope_inflight = 0;
        var requests = window.__periscope_requests = [];
        function record(entry) { requests.push(entry); if (requests.length > 500) requests.shift(); return entry; }

        var originalFetch = window.fetch;
        window.fetch = function(input, init) {
            var url = (input && input.url) || String(input);
            var method = ((init && init.method) || (input && input.method) || 'GET').toUpperCase();
            var entry = record({ method: method, url: url, kind: 'fetch', status: null, start: performance.now() });
            window.__periscope_inflight++;
            return originalFetch.apply(this, arguments)
                .then(function(r) {
                    window.__periscope_inflight--;
                    entry.status = r.status; entry.ms = Math.round(performance.now() - entry.start);
                    return r;
                })
                .catch(function(e) {
                    window.__periscope_inflight--;
                    entry.error = String(e); entry.ms = Math.round(performance.now() - entry.start);
                    throw e;
                });
        };

        var originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
            this.__periscope = { method: String(method || 'GET').toUpperCase(), url: String(url) };
            return originalOpen.apply(this, arguments);
        };
        var originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function() {
            var meta = this.__periscope || { method: 'GET', url: '' };
            var entry = record({ method: meta.method, url: meta.url, kind: 'xhr', status: null, start: performance.now() });
            window.__periscope_inflight++;
            this.addEventListener('loadend', function() {
                window.__periscope_inflight--;
                entry.status = this.status || null; entry.ms = Math.round(performance.now() - entry.start);
            }, { once: true });
            return originalSend.apply(this, arguments);
        };

        window.__periscope_isFetchQuiet = function() {
            return window.__periscope_inflight === 0
                && document.readyState === 'complete';
        };
    })();
    """

    static let checkScript =
        "window.__periscope_isFetchQuiet ? window.__periscope_isFetchQuiet() : true"

    static let readRequestsScript = "JSON.stringify(window.__periscope_requests || [])"
}

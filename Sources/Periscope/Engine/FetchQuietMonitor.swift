import Foundation

enum FetchQuietMonitor {
    static let installScript = """
    (function() {
        if (window.__periscope_installed) return;
        window.__periscope_installed = true;
        window.__periscope_inflight = 0;
        const originalFetch = window.fetch;
        window.fetch = function() {
            window.__periscope_inflight++;
            return originalFetch.apply(this, arguments)
                .then(r => { window.__periscope_inflight--; return r; })
                .catch(e => { window.__periscope_inflight--; throw e; });
        };
        const originalSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function() {
            window.__periscope_inflight++;
            this.addEventListener('loadend',
                () => { window.__periscope_inflight--; }, { once: true });
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
}

import Foundation

/// Records console output and uncaught errors so `periscope console` can show
/// them. Installed at document start, before any page script runs.
enum ConsoleMonitor {
    static let installScript = """
    (function() {
        if (window.__periscope_console) return;
        var log = window.__periscope_console = [];
        function push(level, text, source) {
            log.push({ level: level, text: String(text).slice(0, 2000), source: source || null });
            if (log.length > 500) log.shift();
        }
        function fmt(args) {
            return Array.prototype.map.call(args, function(a) {
                if (typeof a === 'string') return a;
                try { return JSON.stringify(a); } catch (e) { return String(a); }
            }).join(' ');
        }
        ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
            var orig = console[level];
            console[level] = function() {
                push(level, fmt(arguments));
                return orig && orig.apply(console, arguments);
            };
        });
        window.addEventListener('error', function(e) {
            push('error', e.message || String(e.error || e),
                 e.filename ? (e.filename.split('/').pop() + ':' + e.lineno) : null);
        });
        window.addEventListener('unhandledrejection', function(e) {
            push('error', 'Unhandled rejection: ' + (e.reason && e.reason.message || e.reason));
        });
    })();
    """

    static let readScript = "JSON.stringify(window.__periscope_console || [])"
}

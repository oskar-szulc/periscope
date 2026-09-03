import Foundation

/// Produces a compact, LLM-friendly representation of a page's content and
/// interactive elements, designed to fit within a small context window.
enum PageSummarizer {
    /// JavaScript that extracts a structured page summary from the DOM.
    /// Returns a JSON string with text content and interactive elements.
    static let extractScript = """
    (function() {
        var result = { title: document.title, url: location.href, text: '', elements: [] };

        // Extract main text content (truncated)
        var main = document.querySelector('main') || document.querySelector('article') || document.body;
        if (main) {
            var clone = main.cloneNode(true);
            clone.querySelectorAll('script, style, nav, footer, iframe, noscript, svg').forEach(function(el) { el.remove(); });
            result.text = clone.textContent.replace(/\\s+/g, ' ').trim().substring(0, 3000);
        }

        // Extract interactive and semantic elements
        var selectors = 'a[href], button, input, select, textarea, [role=button], [onclick], form, h1, h2, h3, [aria-label]';
        var seen = new Set();
        document.querySelectorAll(selectors).forEach(function(el, i) {
            if (i > 80) return;
            var tag = el.tagName.toLowerCase();
            var entry = { tag: tag };

            if (el.id) entry.id = el.id;
            if (el.className && typeof el.className === 'string') {
                var cls = el.className.trim();
                if (cls) entry.class = cls.split(/\\s+/).slice(0, 3).join(' ');
            }
            if (el.type) entry.type = el.type;
            if (el.name) entry.name = el.name;
            if (el.placeholder) entry.placeholder = el.placeholder;
            if (el.getAttribute('aria-label')) entry.ariaLabel = el.getAttribute('aria-label');
            if (el.getAttribute('role')) entry.role = el.getAttribute('role');
            if (tag === 'a') entry.href = el.getAttribute('href');

            var text = el.textContent.replace(/\\s+/g, ' ').trim();
            if (text && text.length < 100) entry.text = text;

            // Build a unique selector for this element
            var sel = tag;
            if (el.id) { sel = '#' + el.id; }
            else if (el.name) { sel = tag + '[name="' + el.name + '"]'; }
            else if (entry.ariaLabel) { sel = tag + '[aria-label="' + entry.ariaLabel + '"]'; }
            entry.selector = sel;

            var key = sel + '|' + (entry.text || '');
            if (!seen.has(key)) {
                seen.add(key);
                result.elements.push(entry);
            }
        });

        return JSON.stringify(result);
    })();
    """
}

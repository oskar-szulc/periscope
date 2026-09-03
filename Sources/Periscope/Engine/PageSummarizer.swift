import Foundation

/// Produces a compact, LLM-friendly representation of a page's content and
/// interactive elements, designed to fit within a small context window.
///
/// Shared by `state`, `query` and `find`. `state` decodes it into
/// `PageStateData`; the two Apple Intelligence commands hand the JSON to the
/// model as-is.
enum PageSummarizer {
    static let textLimit = 3000
    static let elementLimit = 80

    /// JavaScript that extracts a structured page summary from the DOM.
    ///
    /// Two properties matter for an agent that intends to *act* on the result:
    /// every element is visible and enabled (acting on a hidden control fails),
    /// and every selector is verified to match exactly one node before it is
    /// emitted. A selector that resolves to 12 buttons is worse than none.
    static let extractScript = """
    (function() {
        var TEXT_LIMIT = \(textLimit), ELEMENT_LIMIT = \(elementLimit);
        var result = {
            title: document.title, url: location.href,
            text: '', truncated: false, elements: [], headings: []
        };

        var main = document.querySelector('main') || document.querySelector('article') || document.body;
        if (main) {
            var clone = main.cloneNode(true);
            clone.querySelectorAll('script, style, nav, footer, iframe, noscript, svg')
                .forEach(function(el) { el.remove(); });
            // innerText, not textContent: it respects CSS, so text inside a
            // display:none block does not show up in a summary whose element
            // list correctly excludes that block.
            document.body.appendChild(clone);
            clone.style.position = 'absolute';
            clone.style.left = '-99999px';
            var raw = clone.innerText || clone.textContent;
            clone.remove();
            var full = raw.replace(/\\s+/g, ' ').trim();
            result.text = full.substring(0, TEXT_LIMIT);
            result.truncated = full.length > TEXT_LIMIT;
        }

        // An element an agent cannot see is one it cannot act on.
        function isVisible(el) {
            var rect = el.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) return false;
            var style = getComputedStyle(el);
            return style.visibility !== 'hidden'
                && style.display !== 'none'
                && parseFloat(style.opacity) > 0;
        }

        function quote(value) {
            return '"' + String(value).replace(/\\\\/g, '\\\\\\\\').replace(/"/g, '\\\\"') + '"';
        }

        function unique(sel) {
            try { return document.querySelectorAll(sel).length === 1; }
            catch (e) { return false; }
        }

        // Prefer a stable, readable selector; fall back to a structural path.
        // Each candidate is checked for uniqueness before being accepted, so the
        // selector handed back is always directly usable by click/fill.
        function selectorFor(el) {
            var tag = el.tagName.toLowerCase();

            if (el.id && unique('#' + CSS.escape(el.id))) return '#' + CSS.escape(el.id);

            var attrs = ['name', 'aria-label', 'placeholder', 'data-testid'];
            for (var i = 0; i < attrs.length; i++) {
                var v = el.getAttribute(attrs[i]);
                if (v) {
                    var s = tag + '[' + attrs[i] + '=' + quote(v) + ']';
                    if (unique(s)) return s;
                }
            }
            if (el.type) {
                var t = tag + '[type=' + quote(el.type) + ']';
                if (unique(t)) return t;
            }

            // Structural path, anchored at the nearest id to keep it short.
            var parts = [], node = el;
            while (node && node.nodeType === 1 && node !== document.body) {
                if (node.id && unique('#' + CSS.escape(node.id))) {
                    parts.unshift('#' + CSS.escape(node.id));
                    break;
                }
                var name = node.tagName.toLowerCase();
                var siblings = node.parentNode
                    ? Array.prototype.filter.call(node.parentNode.children, function(c) {
                          return c.tagName === node.tagName;
                      })
                    : [];
                if (siblings.length > 1) {
                    name += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';
                }
                parts.unshift(name);
                node = node.parentNode;
            }
            var path = parts.join(' > ');
            return unique(path) ? path : null;
        }

        var interactive = 'a[href], button, input:not([type=hidden]), select, textarea, '
            + '[role=button], [role=link], [role=checkbox], [role=tab], [onclick], [contenteditable=true]';
        var seen = {};

        Array.prototype.forEach.call(document.querySelectorAll(interactive), function(el) {
            if (result.elements.length >= ELEMENT_LIMIT) return;
            if (!isVisible(el)) return;

            var selector = selectorFor(el);
            if (!selector || seen[selector]) return;
            seen[selector] = true;

            var entry = { selector: selector, tag: el.tagName.toLowerCase() };
            if (el.type) entry.type = el.type;
            if (el.name) entry.name = el.name;

            var label = el.getAttribute('aria-label') || el.placeholder || null;
            if (!label && el.labels && el.labels.length) {
                label = el.labels[0].textContent.replace(/\\s+/g, ' ').trim();
            }
            if (label) entry.label = label;

            var text = (el.value && el.type !== 'password' ? '' : '')
                || el.textContent.replace(/\\s+/g, ' ').trim();
            if (text && text.length <= 100) entry.text = text;

            if (el.tagName === 'A') entry.href = el.getAttribute('href');
            if (el.disabled) entry.disabled = true;
            if (el.checked !== undefined && el.type &&
                (el.type === 'checkbox' || el.type === 'radio')) {
                entry.checked = !!el.checked;
            }

            result.elements.push(entry);
        });

        Array.prototype.forEach.call(document.querySelectorAll('h1, h2, h3'), function(el) {
            if (result.headings.length >= 30 || !isVisible(el)) return;
            var text = el.textContent.replace(/\\s+/g, ' ').trim();
            if (text) {
                result.headings.push({ level: Number(el.tagName.substring(1)), text: text });
            }
        });

        return JSON.stringify(result);
    })();
    """
}

// MARK: - Typed view

struct PageStateElement: Sendable, Codable {
    var selector: String
    var tag: String
    var type: String?
    var name: String?
    var label: String?
    var text: String?
    var href: String?
    var disabled: Bool?
    var checked: Bool?
}

struct PageStateHeading: Sendable, Codable {
    var level: Int
    var text: String
}

/// One call's worth of "where am I and what can I do here".
struct PageStateData: Sendable, Codable {
    var url: String
    var title: String
    var text: String
    var truncated: Bool
    var elements: [PageStateElement]
    var headings: [PageStateHeading]
}

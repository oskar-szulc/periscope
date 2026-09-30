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

    /// JS expression for the page's main content root: the `<main>` with the
    /// most text, else `<article>`, else `<body>`. Not simply the first
    /// `<main>`: Next.js layouts can put an empty shell `<main>` ahead of the
    /// one holding the content, and picking it yields an empty page.
    static let mainContentExpr = """
        (Array.from(document.querySelectorAll('main')).sort(function(a, b) { return b.textContent.length - a.textContent.length; })[0] || document.querySelector('article') || document.body)
        """

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

            var main = \(mainContentExpr);
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

            var P = window.__periscope;
            function isVisible(el) { return P.visible(el); }
            function selectorFor(el) { return P.selectorFor(el); }

            var interactive = 'a[href], button, input:not([type=hidden]), select, textarea, '
                + '[role=button], [role=link], [role=checkbox], [role=tab], [onclick], [contenteditable=true]';
            var seen = {};

            Array.prototype.forEach.call(document.querySelectorAll(interactive), function(el) {
                if (result.elements.length >= ELEMENT_LIMIT) return;
                if (!isVisible(el)) return;

                var selector = selectorFor(el);
                if (!selector || seen[selector]) return;
                seen[selector] = true;

                var entry = { index: result.elements.length + 1, selector: selector, tag: el.tagName.toLowerCase() };
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

            // `@3` in any later target means the third of these, until the page
            // navigates (this state lives on the page, so a new document drops it).
            P.actions = result.elements.map(function(e) { return e.selector; });

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
    /// 1-based; `@index` targets this element in later commands.
    var index: Int?
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
    /// Set by the `state` command, not by the DOM script: a challenge page
    /// still has a URL, a title and text, and an agent must not act on them.
    var blocked: String? = nil
    /// Actions cut by the default cap; nil when nothing was cut.
    var omitted: Int? = nil
}

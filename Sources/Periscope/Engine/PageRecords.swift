import Foundation

/// The deterministic half of `extract`: what a page says about itself, found
/// without a model.
///
/// - `structured`: schema.org entities from JSON-LD and microdata. Sites publish
///   these for search engines (a job page's `JobPosting` carries salary as
///   numbers), so they are cleaner than anything scraped from the rendered page.
/// - `items`: the page's repeated records (job cards, search results, table
///   rows), found by structure alone, so no per-site selectors are needed.
/// - `next`: the pagination link, when there is one.
/// - `text`: the readable content, only when no items were found (an article
///   or a detail page), so the result is never empty-handed.
enum PageRecords {
    /// A group needs this many siblings to count as a list of records.
    static let minItems = 3
    /// A record has at least this many separate text pieces (title, company,
    /// location...), or one fewer plus a link (rank + linked title). Unlinked
    /// two-piece rows (label/value) are layout, not records; one-piece items
    /// are chips, menu entries, paragraphs.
    static let minParts = 3
    static let itemLimit = 500

    /// JS returning `{title, url, structured, items, itemSelector, next, text?}`.
    /// `from` scopes item detection (structured data is page-level, it lives in
    /// the head); `items` skips detection and uses that selector as the records.
    static func script(from: String?, items: String?) -> String {
        let fromJS = from.map(ElementResolver.jsString) ?? "null"
        let itemsJS = items.map(ElementResolver.jsString) ?? "null"
        return """
        (function() {
            var FROM = \(fromJS), ITEMS = \(itemsJS);
            var MIN_ITEMS = \(minItems), MIN_PARTS = \(minParts), ITEM_LIMIT = \(itemLimit);
            var root = FROM ? document.querySelector(FROM) : document.body;
            if (!root) return null;
            var SKIP = 'nav, header, footer, aside, script, style, noscript, template, select, svg';

            // --- structured data -------------------------------------------
            var structured = [];
            document.querySelectorAll('script[type="application/ld+json"]').forEach(function(s) {
                try {
                    [].concat(JSON.parse(s.textContent)).forEach(function(x) {
                        [].concat(x && x['@graph'] ? x['@graph'] : x).forEach(function(y) {
                            if (y && typeof y === 'object') { delete y['@context']; structured.push(y); }
                        });
                    });
                } catch (e) {}  // a malformed block is the site's bug, not ours
            });
            function microValue(p) {
                if (p.hasAttribute('itemscope')) return microdata(p);
                if (p.hasAttribute('content')) return p.getAttribute('content');
                if (p.matches('a[href], link[href], area[href]')) return p.href;
                if (p.matches('img, audio, video, source, iframe, embed')) return p.src;
                if (p.matches('time[datetime]')) return p.getAttribute('datetime');
                if (p.matches('data, meter')) return p.getAttribute('value');
                return p.textContent.replace(/\\s+/g, ' ').trim();
            }
            function microdata(scope) {
                var o = {};
                if (scope.getAttribute('itemtype')) o['@type'] = scope.getAttribute('itemtype').replace(/^https?:\\/\\/schema\\.org\\//, '');
                scope.querySelectorAll('[itemprop]').forEach(function(p) {
                    // Only properties whose nearest scope is this one; nested
                    // scopes collect their own.
                    var owner = (p.hasAttribute('itemscope') ? p.parentElement : p).closest('[itemscope]');
                    if (owner !== scope) return;
                    var v = microValue(p);
                    p.getAttribute('itemprop').split(/\\s+/).forEach(function(k) {
                        o[k] = k in o ? [].concat(o[k], v) : v;
                    });
                });
                return o;
            }
            document.querySelectorAll('[itemscope]:not([itemprop])').forEach(function(s) {
                structured.push(microdata(s));
            });

            // --- repeated records ------------------------------------------
            // A record's text pieces, one per rendered line of text: text
            // flowing through inline markup ("by <a>alice</a> 2h ago",
            // "<em>headless</em> browser", "(<span>site.com</span>)") stays one
            // piece; flex/grid items, blocks and <br> split. Two sibling inline
            // elements with no whitespace between them are styled apart
            // (margins, badges), so they split too.
            var FORMATTING = /^(EM|STRONG|B|I|U|S|MARK|CODE|KBD|ABBR|SUB|SUP|SMALL|Q|CITE|DFN|TIME)$/;
            var displays = new Map();
            function blockOf(el) {
                for (; el && el !== root; el = el.parentElement) {
                    var d = displays.get(el);
                    if (d === undefined) { d = getComputedStyle(el).display; displays.set(el, d); }
                    if (d !== 'inline' && d !== 'contents') return el;
                }
                return root;
            }
            function parts(el) {
                var out = [], buf = '', block = null, prev = null, n;
                function flush() { var t = buf.replace(/\\s+/g, ' ').trim(); if (t) out.push(t); buf = ''; }
                var w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
                while ((n = w.nextNode())) {
                    if (n.nodeType === 1) { if (n.tagName === 'BR') flush(); continue; }
                    var p = n.parentElement, text = n.textContent;
                    if (!p || p.closest('script, style, noscript, template')) continue;
                    if (!text.trim()) { if (buf) buf += ' '; continue; }  // the space between two <em>s
                    if (p.checkVisibility && !p.checkVisibility()) continue;
                    var b = blockOf(p);
                    var flows = /\\s$/.test(buf) || /^\\s/.test(text) || !prev ||
                        p.contains(prev) || prev.contains(p) ||
                        FORMATTING.test(p.tagName) || FORMATTING.test(prev.tagName);
                    if (b !== block || !flows) flush();
                    buf += text; block = b; prev = p;
                }
                flush();
                return out;
            }
            function sig(el) {
                return el.tagName.toLowerCase() + Array.from(el.classList).sort().map(function(c) {
                    return '.' + CSS.escape(c);
                }).join('');
            }
            // Page chrome inside root is skipped; chrome the caller scoped
            // into with --from is not.
            function inSkipped(el) {
                var s = el.closest(SKIP);
                return s && s !== root && root.contains(s);
            }

            var chosen = null, selector = null;
            if (ITEMS) {
                chosen = Array.from(root.querySelectorAll(ITEMS));
                selector = ITEMS;
            } else {
                // Siblings sharing a tag+class signature, pooled page-wide by
                // parent signature too: cards split across several same-styled
                // sections are one list, not several short ones.
                var groups = {};
                [root].concat(Array.from(root.querySelectorAll('*'))).forEach(function(parent) {
                    if (inSkipped(parent)) return;
                    var bySig = {};
                    Array.from(parent.children).forEach(function(c) {
                        if (inSkipped(c)) return;
                        (bySig[sig(c)] = bySig[sig(c)] || []).push(c);
                    });
                    Object.keys(bySig).forEach(function(k) {
                        if (bySig[k].length < 2) return;
                        var key = sig(parent) + ' > ' + k;
                        groups[key] = (groups[key] || []).concat(bySig[k]);
                    });
                });
                // Pooling by signature can catch nested layout (table rows
                // holding tables of rows); keep only the innermost members.
                Object.keys(groups).forEach(function(key) {
                    var members = new Set(groups[key]), outer = new Set();
                    groups[key].forEach(function(e) {
                        for (var a = e.parentElement; a && a !== root; a = a.parentElement)
                            if (members.has(a)) outer.add(a);
                    });
                    if (outer.size) groups[key] = groups[key].filter(function(e) { return !outer.has(e); });
                });
                var candidates = [];
                Object.keys(groups).forEach(function(key) {
                    var els = groups[key];
                    if (els.length < MIN_ITEMS) return;
                    var rich = 0, len = 0;
                    els.forEach(function(e) {
                        var ps = parts(e);
                        if (ps.length >= MIN_PARTS || (ps.length >= 2 && e.querySelector('a[href]'))) rich++;
                        len += Math.min(ps.join(' ').length, 300);
                    });
                    // Total text with each record capped: many substantial
                    // records beat a few huge wrappers.
                    if (rich * 2 >= els.length) candidates.push({ els: els, key: key, len: len });
                });
                candidates.sort(function(a, b) { return b.len - a.len; });
                var best = candidates[0];
                // Wrappers (sections of cards) still carry all their records'
                // text. Descend while an inner group has more records and
                // covers most of the text.
                for (var moved = true; best && moved;) {
                    moved = false;
                    for (var i = 0; i < candidates.length; i++) {
                        var c = candidates[i];
                        if (c.els.length > best.els.length && c.len * 2 >= best.len &&
                            c.els.every(function(e) { return best.els.some(function(w) { return w !== e && w.contains(e); }); })) {
                            best = c; moved = true; break;
                        }
                    }
                }
                if (best) { chosen = best.els; selector = best.key; }
            }

            var items = [];
            (chosen || []).slice(0, ITEM_LIMIT).forEach(function(el) {
                if (el.tagName === 'TR' && !el.querySelector('td')) return;  // header row
                var item = { text: parts(el) };
                var seen = {}, links = [];
                (el.matches('a[href]') ? [el] : []).concat(Array.from(el.querySelectorAll('a[href]'))).forEach(function(a) {
                    if (!/^https?:/.test(a.href)) return;
                    var text = a.textContent.replace(/\\s+/g, ' ').trim();
                    // An image link and a title link often share a URL; keep the words.
                    if (seen[a.href]) { if (!seen[a.href].text) seen[a.href].text = text; return; }
                    links.push(seen[a.href] = { text: text, url: a.href });
                });
                if (links.length) item.links = links;
                var img = el.querySelector('img');
                if (img && img.currentSrc && /^https?:/.test(img.currentSrc)) item.image = img.currentSrc;
                // Table rows: key the cells by the column headers.
                var table = el.tagName === 'TR' && el.closest('table');
                var head = table && (table.querySelector('thead tr') || table.querySelector('tr'));
                if (head && head !== el && head.querySelector('th')) {
                    var names = Array.from(head.children).map(function(c) { return c.textContent.replace(/\\s+/g, ' ').trim(); });
                    var fields = {};
                    Array.from(el.children).forEach(function(c, i) {
                        if (names[i]) fields[names[i]] = c.textContent.replace(/\\s+/g, ' ').trim();
                    });
                    item.fields = fields;
                }
                items.push(item);
            });

            // --- pagination -------------------------------------------------
            var next = document.querySelector('link[rel="next"], a[rel~="next"]');
            if (!next) {
                next = Array.from(document.querySelectorAll('a[href]')).find(function(a) {
                    var t = (a.textContent + ' ' + (a.getAttribute('aria-label') || '')).replace(/\\s+/g, ' ').trim();
                    return /^(?:(?:next(?: page)?|older posts)\\s*[›»→]?|[›»→])$/i.test(t);
                });
            }

            var result = {
                title: document.title, url: location.href,
                structured: structured, items: items,
                itemSelector: items.length ? selector : null,
                next: next && next.href ? next.href : null
            };
            if (chosen && chosen.length > ITEM_LIMIT) result.itemsTruncated = chosen.length;
            return result;
        })()
        """
    }

    /// One line per record for the model: the model sees record boundaries
    /// instead of guessing them, and line-based chunking never severs a record.
    static func modelInput(_ records: [String: Any]) -> String {
        var lines: [String] = []
        for entity in records["structured"] as? [Any] ?? [] {
            if let data = try? JSONSerialization.data(withJSONObject: entity, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                lines.append("structured data: " + json)
            }
        }
        for case let item as [String: Any] in records["items"] as? [Any] ?? [] {
            var line = "- " + ((item["text"] as? [String]) ?? []).joined(separator: " | ")
            let links = (item["links"] as? [[String: String]] ?? [])
                .map { "\($0["text"] ?? "") <\($0["url"] ?? "")>" }
            if !links.isEmpty { line += " | links: " + links.joined(separator: "; ") }
            lines.append(line)
        }
        if let text = records["text"] as? String, !text.isEmpty { lines.append(text) }
        return lines.joined(separator: "\n")
    }
}

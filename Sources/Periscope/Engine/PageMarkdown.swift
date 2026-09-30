import Foundation

/// `text`: the rendered page as markdown, read from the live DOM.
///
/// Not a second parse of the HTML: the browser has already decided what is
/// visible, what CSS hid and what script built, so this walks what it rendered.
/// Text comes only from visible nodes (an icon font's empty `<i>` has none),
/// line breaks follow each element's computed `display`, and links are
/// absolute. It replaced a regex HTML-to-markdown converter that re-parsed
/// `innerHTML` and needed a special case for every markup quirk.
enum PageMarkdown {
    /// JS returning the markdown string, or null when `selector` matches nothing.
    static func script(selector: String?, links: Bool, images: Bool) -> String {
        """
        (function() {
            var root = \(PageSummarizer.rootExpr(selector)), LINKS = \(links), IMAGES = \(images);
            if (!root) return null;
            var SKIP = 'script, style, noscript, template, iframe, svg, nav, footer';
            var shown = new Map(), displays = new Map();
            function visible(el) {
                var v = shown.get(el);
                if (v === undefined) { v = !el.checkVisibility || el.checkVisibility(); shown.set(el, v); }
                return v;
            }
            function display(el) {
                var d = displays.get(el);
                if (d === undefined) { d = getComputedStyle(el).display; displays.set(el, d); }
                return d;
            }
            function isBlock(el) { return !/^(inline|contents|none)/.test(display(el)); }
            function block(s) { return '\\n\\n' + s + '\\n\\n'; }
            function inner(el, depth) {
                var out = '';
                for (var n = el.firstChild; n; n = n.nextSibling) out += render(n, depth);
                return out;
            }
            function flat(s) { return s.replace(/\\s+/g, ' ').trim(); }

            function list(el, depth) {
                var i = 0, lines = [];
                for (var c = el.firstElementChild; c; c = c.nextElementSibling) {
                    if (c.tagName !== 'LI' || !visible(c)) continue;
                    i++;
                    var marker = el.tagName === 'OL' ? i + '. ' : '- ';
                    var body = inner(c, depth + 1).replace(/\\n{3,}/g, '\\n\\n').trim();
                    if (!body) continue;
                    var pad = new Array(depth + 1).join('  ');
                    // A nested list is already indented; other continuation lines go under the marker.
                    var rest = body.split('\\n').filter(Boolean);
                    lines.push(pad + marker + rest.shift());
                    rest.forEach(function(l) { lines.push(/^ +(- |\\d+\\. )/.test(l) ? l : pad + '  ' + l); });
                }
                return lines.length ? block(lines.join('\\n')) : '';
            }

            function table(el, depth) {
                // A table holding tables, or marked presentational, lays the page
                // out (Hacker News); its rows are blocks, not a markdown table.
                if (el.getAttribute('role') === 'presentation' || el.querySelector('table')) {
                    return block(Array.from(el.rows).filter(visible).map(function(r) {
                        return Array.from(r.cells).map(function(c) { return inner(c, depth); }).join(' ');
                    }).join('\\n\\n'));
                }
                var rows = Array.from(el.rows).filter(visible).map(function(r) {
                    return Array.from(r.cells).map(function(c) { return flat(inner(c, 0)).replace(/\\|/g, '\\\\|'); });
                }).filter(function(r) { return r.some(Boolean); });
                if (!rows.length) return '';
                var width = Math.max.apply(null, rows.map(function(r) { return r.length; }));
                function line(r) { var c = r.slice(); while (c.length < width) c.push(''); return '| ' + c.join(' | ') + ' |'; }
                var head = el.rows[0] && el.rows[0].querySelector('th');
                var out = [line(rows[0])];
                if (head) out.push(line(rows[0].map(function() { return '---'; })));
                rows.slice(1).forEach(function(r) { out.push(line(r)); });
                return block(out.join('\\n'));
            }

            function render(n, depth) {
                if (n.nodeType === 3) return n.textContent.replace(/\\s+/g, ' ');
                if (n.nodeType !== 1) return '';
                if (n !== root && n.matches(SKIP)) return '';
                if (!visible(n)) return '';
                var tag = n.tagName, t;
                switch (tag) {
                case 'BR': return '\\n';
                case 'HR': return block('---');
                case 'H1': case 'H2': case 'H3': case 'H4': case 'H5': case 'H6':
                    t = flat(inner(n, depth));
                    return t ? block(new Array(+tag[1] + 1).join('#') + ' ' + t) : '';
                case 'UL': case 'OL': return list(n, depth);
                case 'TABLE': return table(n, depth);
                case 'PRE': return block('```\\n' + n.innerText.replace(/\\n+$/, '') + '\\n```');
                case 'CODE': t = n.textContent; return t.trim() ? '`' + t + '`' : '';
                case 'STRONG': case 'B': t = flat(inner(n, depth)); return t ? '**' + t + '**' : '';
                case 'EM': case 'I': t = flat(inner(n, depth)); return t ? '*' + t + '*' : '';
                case 'IMG':
                    t = (n.getAttribute('alt') || '').trim();
                    return IMAGES && n.currentSrc ? '![' + t + '](' + n.currentSrc + ')' : t;
                case 'A':
                    t = flat(inner(n, depth));
                    if (!t) return '';
                    return LINKS && /^(https?:|mailto:)/.test(n.href) ? '[' + t + '](' + n.href + ')' : t;
                case 'BLOCKQUOTE':
                    t = inner(n, depth).replace(/\\n{3,}/g, '\\n\\n').trim();
                    return t ? block(t.split('\\n').map(function(l) { return '> ' + l; }).join('\\n')) : '';
                }
                t = inner(n, depth);
                return isBlock(n) ? block(t) : t;
            }

            // Per line: drop trailing space, and leading space unless it indents
            // a nested list item; then at most one blank line in a row.
            return render(root, 0).split('\\n').map(function(l) {
                l = l.replace(/[ \\t]+$/, '');
                return /^ +(- |\\d+\\. )/.test(l) ? l : l.replace(/^[ \\t]+/, '');
            }).join('\\n').replace(/\\n{3,}/g, '\\n\\n').trim();
        })()
        """
    }
}

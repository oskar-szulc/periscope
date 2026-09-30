import Foundation

/// Turns a target string into DOM elements, and DOM elements back into
/// selectors an agent can reuse.
///
/// A target is CSS unless it carries one of four prefixes:
///
///     text:Next                    element whose visible text is "Next" (exact, then contains)
///     label:Search Wikipedia       control labelled that way (aria-label, <label>, title)
///     placeholder:Email            input with that placeholder
///     role:button name=Sign in     element with that role and accessible name
///
/// These exist because the selector an agent can *see* on a page is its text or
/// its label, not its class name. All matching is whitespace-collapsed and
/// case-insensitive, and prefers exact matches over substring matches.
enum ElementResolver {
    /// How long an action waits for its target to exist, be visible and be
    /// enabled before giving up. SPA controls routinely appear a few hundred
    /// milliseconds after `load`; failing instantly turned those into "not found".
    static let actionabilityWaitMs = 5000

    static func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }

    /// JavaScript helpers shared by every script here and by `PageSummarizer`,
    /// so a selector printed by `state` resolves the same way `click` resolves it.
    /// Evaluates to an object: `{ query, selectorFor, describe, visible, actionable }`.
    static let preludeJS = """
    (function() {
        function norm(s) { return (s == null ? '' : String(s)).replace(/\\s+/g, ' ').trim().toLowerCase(); }
        function quote(v) { return '"' + String(v).replace(/\\\\/g, '\\\\\\\\').replace(/"/g, '\\\\"') + '"'; }
        function unique(sel) { try { return document.querySelectorAll(sel).length === 1; } catch (e) { return false; } }

        function visible(el) {
            if (!el || !el.getBoundingClientRect) return false;
            var r = el.getBoundingClientRect();
            if (r.width === 0 && r.height === 0) return false;
            var st = getComputedStyle(el);
            return st.visibility !== 'hidden' && st.display !== 'none' && parseFloat(st.opacity) > 0;
        }
        function actionable(el) {
            if (!visible(el)) return { ok: false, reason: 'not visible' };
            if (el.disabled || el.getAttribute('aria-disabled') === 'true') return { ok: false, reason: 'disabled' };
            return { ok: true };
        }

        function nameOf(el) {
            var n = el.getAttribute('aria-label');
            if (!n && el.labels && el.labels.length) n = el.labels[0].textContent;
            if (!n) n = el.getAttribute('placeholder') || el.getAttribute('title') || el.getAttribute('alt');
            if (!n && el.tagName === 'INPUT' && (el.type === 'submit' || el.type === 'button' || el.type === 'reset')) n = el.value;
            if (!n) n = el.textContent;
            return norm(n);
        }
        // Exact matches win; otherwise substring matches. Never mix the two.
        function preferExact(pairs, wanted) {
            var w = norm(wanted), exact = [], partial = [];
            pairs.forEach(function(p) {
                if (!p.s) return;
                if (p.s === w) exact.push(p.el);
                else if (p.s.indexOf(w) !== -1) partial.push(p.el);
            });
            return exact.length ? exact : partial;
        }
        function innermost(els) {
            return els.filter(function(e) { return !els.some(function(o) { return o !== e && e.contains(o); }); });
        }
        var roleMap = {
            button: 'button, input[type=button], input[type=submit], input[type=reset], [role=button]',
            link: 'a[href], [role=link]',
            textbox: 'input:not([type]), input[type=text], input[type=email], input[type=url], input[type=tel], input[type=number], input[type=password], textarea, [role=textbox], [contenteditable=true]',
            searchbox: 'input[type=search], [role=searchbox]',
            checkbox: 'input[type=checkbox], [role=checkbox]',
            radio: 'input[type=radio], [role=radio]',
            combobox: 'select, [role=combobox]',
            heading: 'h1, h2, h3, h4, h5, h6, [role=heading]',
            tab: '[role=tab]', menuitem: '[role=menuitem]', option: 'option, [role=option]'
        };

        function query(target) {
            var m = /^(text|label|placeholder|role):([\\s\\S]*)$/.exec(target);
            if (!m) return Array.prototype.slice.call(document.querySelectorAll(target));
            var kind = m[1], arg = m[2].trim();
            var all = Array.prototype.slice.call(document.querySelectorAll('body *'));

            if (kind === 'text') {
                var w = norm(arg);
                var texty = all.filter(function(e) {
                    if (e.tagName === 'SCRIPT' || e.tagName === 'STYLE') return false;
                    var t = norm(e.textContent);
                    return t && t.length <= 300 && t.indexOf(w) !== -1;
                });
                return innermost(preferExact(texty.map(function(e) { return { el: e, s: norm(e.textContent) }; }), arg));
            }
            if (kind === 'label') {
                var pairs = [];
                all.forEach(function(e) {
                    if (e.tagName === 'LABEL') {
                        var c = e.control || (e.htmlFor ? document.getElementById(e.htmlFor) : e.querySelector('input, select, textarea, button'));
                        if (c) pairs.push({ el: c, s: norm(e.textContent) });
                        return;
                    }
                    var al = e.getAttribute('aria-label');
                    if (al) pairs.push({ el: e, s: norm(al) });
                    else if (e.getAttribute('title')) pairs.push({ el: e, s: norm(e.getAttribute('title')) });
                });
                var found = preferExact(pairs, arg), out = [];
                found.forEach(function(e) { if (out.indexOf(e) === -1) out.push(e); });
                return out;
            }
            if (kind === 'placeholder') {
                return preferExact(all.filter(function(e) { return e.getAttribute('placeholder'); })
                    .map(function(e) { return { el: e, s: norm(e.getAttribute('placeholder')) }; }), arg);
            }
            var rm = /^([\\w-]+)(?:\\s+name=([\\s\\S]+))?$/.exec(arg);
            if (!rm) return [];
            var sel = roleMap[rm[1]] || ('[role=' + rm[1] + ']');
            var els = Array.prototype.slice.call(document.querySelectorAll(sel));
            if (!rm[2]) return els;
            return preferExact(els.map(function(e) { return { el: e, s: nameOf(e) }; }), rm[2].replace(/^["']|["']$/g, ''));
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
                if (v) { var s = tag + '[' + attrs[i] + '=' + quote(v) + ']'; if (unique(s)) return s; }
            }
            if (el.type) { var t = tag + '[type=' + quote(el.type) + ']'; if (unique(t)) return t; }
            var parts = [], node = el;
            while (node && node.nodeType === 1 && node !== document.body) {
                if (node.id && unique('#' + CSS.escape(node.id))) { parts.unshift('#' + CSS.escape(node.id)); break; }
                var name = node.tagName.toLowerCase();
                var siblings = node.parentNode
                    ? Array.prototype.filter.call(node.parentNode.children, function(c) { return c.tagName === node.tagName; })
                    : [];
                if (siblings.length > 1) name += ':nth-of-type(' + (siblings.indexOf(node) + 1) + ')';
                parts.unshift(name);
                node = node.parentNode;
            }
            var path = parts.join(' > ');
            return unique(path) ? path : null;
        }

        // One line an agent can paste: unique selector, tag[type], label, text.
        function describe(el) {
            var d = selectorFor(el) || '(no unique selector)';
            d += '  ' + el.tagName.toLowerCase() + (el.type ? '[' + el.type + ']' : '');
            var label = el.getAttribute('aria-label')
                || (el.labels && el.labels.length ? el.labels[0].textContent : '')
                || el.getAttribute('placeholder') || '';
            if (label) d += ' label=' + quote(label.replace(/\\s+/g, ' ').trim());
            var text = el.textContent.replace(/\\s+/g, ' ').trim();
            if (text && text !== label) d += ' ' + quote(text.length > 60 ? text.slice(0, 57) + '...' : text);
            return d;
        }

        return { query: query, selectorFor: selectorFor, describe: describe, visible: visible, actionable: actionable, norm: norm };
    })
    """

    /// Injected once at document start (see HiddenWindowController) so every
    /// action and `state` reference one resolver object instead of re-shipping
    /// and re-parsing the ~140-line prelude in each generated script.
    static var installScript: String { "if (!window.__periscope) window.__periscope = (\(preludeJS))();" }

    /// Wrap a script body so `P` is the resolver and `T` the target.
    private static func wrap(target: String, _ body: String) -> String {
        "(function() { var P = window.__periscope; var T = \(jsString(target)); \(body) })()"
    }

    static func countScript(selector: String) -> String {
        wrap(target: selector, "return P.query(T).length;")
    }

    static func existsScript(selector: String) -> String {
        wrap(target: selector, "return P.query(T).length > 0;")
    }

    /// Everything `resolveElement` needs in one round trip.
    static func probeScript(selector: String) -> String {
        wrap(target: selector, """
            var els = P.query(T);
            var first = els[0];
            var act = first ? P.actionable(first) : { ok: false, reason: 'not found' };
            return JSON.stringify({
                count: els.length,
                actionable: act.ok,
                reason: act.reason || null,
                candidates: els.slice(0, 5).map(P.describe)
            });
        """)
    }

    static func clickScript(selector: String) -> String {
        wrap(target: selector, "P.query(T)[0].click();")
    }

    static func fillScript(selector: String, value: String) -> String {
        wrap(target: selector, """
            var el = P.query(T)[0];
            var v = \(jsString(value));
            el.focus();
            if (el.isContentEditable) {
                el.textContent = v;
            } else {
                var proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
                var desc = Object.getOwnPropertyDescriptor(proto, 'value');
                if (desc && desc.set) desc.set.call(el, v); else el.value = v;
            }
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
        """)
    }

    /// Press Enter in a field the way a person would: key events first, and
    /// the owning form's submit only if nothing handled the key.
    static func pressEnterScript(selector: String) -> String {
        wrap(target: selector, """
            var el = P.query(T)[0];
            el.focus();
            var opts = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
            var handled = !el.dispatchEvent(new KeyboardEvent('keydown', opts));
            el.dispatchEvent(new KeyboardEvent('keypress', opts));
            el.dispatchEvent(new KeyboardEvent('keyup', opts));
            if (!handled && el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }
        """)
    }

    static func selectScript(selector: String, value: String) -> String {
        wrap(target: selector, """
            var el = P.query(T)[0];
            el.value = \(jsString(value));
            el.dispatchEvent(new Event('change', { bubbles: true }));
        """)
    }

    static func checkScript(selector: String, checked: Bool) -> String {
        wrap(target: selector, """
            var el = P.query(T)[0];
            if (el.checked !== \(checked)) {
                el.checked = \(checked);
                el.dispatchEvent(new Event('change', { bubbles: true }));
            }
        """)
    }

    /// `requestSubmit` runs the page's submit handlers and validation, which is
    /// what an SPA relies on; bare `submit()` bypasses both.
    static func submitScript(selector: String?) -> String {
        let find = selector.map { "var el = P.query(\(jsString($0)))[0]; var form = el.tagName === 'FORM' ? el : (el.form || el.closest('form'));" }
            ?? "var form = document.forms[0];"
        return """
        (function() { var P = window.__periscope; \(find)
            if (!form) throw new Error('No form found');
            form.requestSubmit ? form.requestSubmit() : form.submit();
        })()
        """
    }

    static func scrollScript(target: String) -> String {
        switch target {
        case "up": return "window.scrollBy(0, -window.innerHeight)"
        case "down": return "window.scrollBy(0, window.innerHeight)"
        case "top": return "window.scrollTo(0, 0)"
        case "bottom": return "window.scrollTo(0, document.body.scrollHeight)"
        default:
            return wrap(target: target, "P.query(T)[0].scrollIntoView({ behavior: 'instant', block: 'center' });")
        }
    }

    /// Focus the target and select what it holds, so typed keys replace it.
    static func focusForTypingScript(selector: String) -> String {
        wrap(target: selector, """
            var el = P.query(T)[0];
            el.focus();
            if (el.select) { el.select(); }
            else if (el.isContentEditable) {
                var r = document.createRange(); r.selectNodeContents(el);
                var s = getSelection(); s.removeAllRanges(); s.addRange(r);
            }
        """)
    }

    static func hoverScript(selector: String) -> String {
        wrap(target: selector, """
            var el = P.query(T)[0];
            el.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
            el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
        """)
    }

    static func elementsScript(selector: String) -> String {
        wrap(target: selector, """
            return P.query(T).map(function(el, i) {
                return { index: i + 1, tag: el.tagName.toLowerCase(), id: el.id || null,
                         classes: Array.prototype.slice.call(el.classList),
                         text: el.textContent.trim().substring(0, 80) };
            });
        """)
    }
}

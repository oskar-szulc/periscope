import Foundation

enum ElementResolver {
    static func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "'\(escaped)'"
    }

    static func countScript(selector: String) -> String {
        "document.querySelectorAll(\(jsString(selector))).length"
    }

    static func existsScript(selector: String) -> String {
        "document.querySelector(\(jsString(selector))) !== null"
    }

    static func clickScript(selector: String) -> String {
        "document.querySelector(\(jsString(selector))).click()"
    }

    static func fillScript(selector: String, value: String) -> String {
        """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            var setter = Object.getOwnPropertyDescriptor(
                window.HTMLInputElement.prototype, 'value').set;
            setter.call(el, \(jsString(value)));
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
        })();
        """
    }

    static func selectScript(selector: String, value: String) -> String {
        """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            el.value = \(jsString(value));
            el.dispatchEvent(new Event('change', { bubbles: true }));
        })();
        """
    }

    static func checkScript(selector: String, checked: Bool) -> String {
        """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            if (el.checked !== \(checked)) {
                el.checked = \(checked);
                el.dispatchEvent(new Event('change', { bubbles: true }));
            }
        })();
        """
    }

    static func submitScript(selector: String?) -> String {
        if let selector {
            return "document.querySelector(\(jsString(selector))).submit()"
        }
        return "document.forms[0].submit()"
    }

    static func scrollScript(target: String) -> String {
        switch target {
        case "up": return "window.scrollBy(0, -window.innerHeight)"
        case "down": return "window.scrollBy(0, window.innerHeight)"
        case "top": return "window.scrollTo(0, 0)"
        case "bottom": return "window.scrollTo(0, document.body.scrollHeight)"
        default:
            return "document.querySelector(\(jsString(target))).scrollIntoView({ behavior: 'instant', block: 'center' })"
        }
    }

    static func hoverScript(selector: String) -> String {
        """
        (function() {
            var el = document.querySelector(\(jsString(selector)));
            el.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
            el.dispatchEvent(new MouseEvent('mouseover', { bubbles: true }));
        })();
        """
    }
}

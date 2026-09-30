import AppKit
import WebKit

/// Real AppKit events sent to the page's window. The page sees them as trusted
/// (`event.isTrusted`), with real `event.code`s, unlike events dispatched from
/// JS, which anti-bot scripts check for.
extension HiddenWindowController {
    /// Page viewport coordinates (top-left origin, CSS px) to window coordinates.
    private func windowPoint(x: Double, y: Double) -> NSPoint {
        NSPoint(x: x, y: (window.contentView?.bounds.height ?? 0) - y)
    }

    func mouse(_ type: NSEvent.EventType, x: Double, y: Double) {
        guard let event = NSEvent.mouseEvent(
            with: type, location: windowPoint(x: x, y: y), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1,
            pressure: type == .leftMouseDown || type == .leftMouseDragged ? 1 : 0)
        else { return }
        window.sendEvent(event)
    }

    func scrollWheel(x: Double, y: Double, dx: Double, dy: Double) {
        // Wheel deltas point the other way from scroll offsets.
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                               wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0) else { return }
        // An NSEvent made from a CGEvent has no window, so its locationInWindow
        // is the CG location flipped into screen space, and sendEvent hit-tests
        // that as a window point: aim the flip at the window point itself.
        let point = windowPoint(x: x, y: y)
        cg.location = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        if let event = NSEvent(cgEvent: cg) { window.sendEvent(event) }
    }

    /// One character as a key down/up pair, on the web view so it reaches the
    /// focused element.
    func key(_ character: Character) {
        if let web = webView, window.firstResponder !== web { window.makeFirstResponder(web) }
        let text = String(character)
        let (code, shift) = Self.keyCode(for: character)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: shift ? .shift : [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code) {
                window.sendEvent(event)
            }
        }
    }

    private var webView: WKWebView? {
        func find(_ view: NSView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            for sub in view.subviews { if let web = find(sub) { return web } }
            return nil
        }
        return window.contentView.flatMap(find)
    }

    /// US ANSI virtual key codes, and whether the character needs Shift.
    /// ponytail: US layout only; other layouts type the right text but report
    /// US `event.code`s. Characters outside it (é, emoji) send key code 0.
    nonisolated static func keyCode(for character: Character) -> (UInt16, Bool) {
        if let code = unshifted[character] { return (code, false) }
        if let base = shifted[character], let code = unshifted[base] { return (code, true) }
        if character.isUppercase, let lower = character.lowercased().first, let code = unshifted[lower] {
            return (code, true)
        }
        return (0, false)
    }

    nonisolated private static let unshifted: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "\r": 36, "\n": 36,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45,
        "m": 46, ".": 47, "\t": 48, " ": 49, "`": 50,
    ]
    nonisolated private static let shifted: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
        "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";",
        "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]
}

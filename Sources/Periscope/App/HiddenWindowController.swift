import AppKit
import SwiftUI
import WebKit

@MainActor
final class HiddenWindowController {
    let window: NSWindow
    // Will become: let page: WebPage
    // For now, use WKWebView as a stand-in
    let webView: WKWebView

    init(viewportWidth: Int = 1920, viewportHeight: Int = 1080) {
        let config = WKWebViewConfiguration()
        self.webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight),
            configuration: config
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: viewportWidth, height: viewportHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.level = .init(rawValue: -1000)
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        window.contentView = webView
        window.orderFront(nil)
        self.window = window
    }

    func resize(width: Int, height: Int) {
        window.setContentSize(NSSize(width: width, height: height))
    }

    func close() {
        window.close()
    }
}

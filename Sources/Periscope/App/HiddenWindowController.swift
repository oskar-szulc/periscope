import AppKit
import SwiftUI
import WebKit

@MainActor
final class HiddenWindowController {
    let page: WebPage
    let window: NSWindow
    let responseRecorder = ResponseRecorder()
    /// The cookie jar lives here, independent of any loaded page.
    let dataStore: WKWebsiteDataStore

    init(viewportWidth: Int = 1920, viewportHeight: Int = 1080) {
        let configuration = WebPage.Configuration()
        // Installed before any page script runs, so requests fired during
        // parsing are counted by `fetchquiet` and logged for `requests`, and
        // console output from the first script onward is kept for `console`.
        for source in [ElementResolver.installScript, FetchQuietMonitor.installScript, ConsoleMonitor.installScript] {
            configuration.userContentController.addUserScript(WKUserScript(
                source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        self.dataStore = configuration.websiteDataStore
        self.page = WebPage(
            configuration: configuration,
            navigationDecider: NavigationObserver(recorder: responseRecorder))

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
        window.contentView = NSHostingView(rootView: WebView(page))
        window.orderFront(nil)
        self.window = window
    }

    func resize(width: Int, height: Int) {
        window.setContentSize(NSSize(width: width, height: height))
    }

    func showWindow(width: Int = 390, height: Int = 844) {
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: width, height: height))
        window.alphaValue = 1.0
        window.level = .floating
        window.collectionBehavior = []
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        window.alphaValue = 0.01
        window.level = .init(rawValue: -1000)
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        window.styleMask = [.borderless]
    }

    func close() {
        window.close()
    }
}

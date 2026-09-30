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
    private var screenObserver: NSObjectProtocol?

    /// What real Safari appends to WebKit's user agent. An embedder gets
    /// neither token by default, and "AppleWebKit ... (KHTML, like Gecko)" with
    /// nothing after it reads as a WebKit that is not Safari: a headless tell,
    /// and the one fingerprint gap found when Cloudflare stalled periscope.
    static let safariProduct: String = {
        let info = NSDictionary(contentsOfFile: "/Applications/Safari.app/Contents/Info.plist")
        let version = info?["CFBundleShortVersionString"] as? String ?? {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return "\(os.majorVersion).\(os.minorVersion)"
        }()
        return "Version/\(version) Safari/605.1.15"
    }()

    init(viewportWidth: Int = 1920, viewportHeight: Int = 1080) {
        var configuration = WebPage.Configuration()
        configuration.applicationNameForUserAgent = Self.safariProduct
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
        window.contentView = NSHostingView(rootView: WebView(page))
        self.window = window
        hideWindow()
        window.orderFront(nil)
        // A display unplugged or rearranged would strand the strip off-screen.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.window.styleMask == [.borderless] else { return }
                self.park()
            }
        }
    }

    /// The hidden window must still count as visible to macOS: an occluded
    /// window's page gets `visibilityState: "hidden"` and no
    /// `requestAnimationFrame`, so rAF-driven pages never finish rendering
    /// (React streaming leaves its content in `<div hidden>`). Below the
    /// desktop or wholly off-screen both count as occluded, so the window
    /// keeps one 1%-opaque pixel column on the right edge of the rightmost
    /// screen, the rest hanging off it, above the Dock (which could cover the
    /// strip) and transparent to clicks.
    private func park() {
        guard let screen = NSScreen.screens.max(by: { $0.frame.maxX < $1.frame.maxX })?.frame else { return }
        window.setFrameOrigin(NSPoint(x: screen.maxX - 1, y: screen.minY))
    }

    func resize(width: Int, height: Int) {
        window.setContentSize(NSSize(width: width, height: height))
    }

    func showWindow(width: Int = 390, height: Int = 844) {
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: width, height: height))
        window.alphaValue = 1.0
        window.level = .floating
        window.ignoresMouseEvents = false
        window.collectionBehavior = []
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideWindow() {
        window.alphaValue = 0.01
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.styleMask = [.borderless]
        park()
    }

    func close() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        window.close()
    }
}

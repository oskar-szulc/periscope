import AppKit

enum AppRunner {
    @MainActor
    static func run(work: @escaping @Sendable () async -> Void) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate {
            Task {
                await work()
                NSApp.terminate(nil)
            }
        }
        app.delegate = delegate
        app.run()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var onReady: (() -> Void)?

    init(onReady: @escaping () -> Void) {
        self.onReady = onReady
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        onReady?()
        onReady = nil
    }
}

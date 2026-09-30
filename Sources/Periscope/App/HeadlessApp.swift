import AppKit

enum AppRunner {
    /// Boots the app every in-process run and `login` share. Inside a sandbox the
    /// window server is denied and this would hang, not fail, so it refuses here,
    /// the one place that needs it.
    @MainActor
    static func run(json: Bool, work: @escaping @Sendable () async -> Void) {
        if Sandbox.isActive {
            let error = makeFormatter(json: json).formatError(ErrorPayload(Sandbox.error))
            if json { print(error) } else { FileHandle.standardError.write(Data((error + "\n").utf8)) }
            exit(Sandbox.error.exitCode)
        }
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

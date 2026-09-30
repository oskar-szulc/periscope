import Darwin

/// Whether this process runs under a macOS sandbox (Claude Code's Bash
/// sandbox, `sandbox-exec`). Inside one, periscope can reach neither the
/// window server nor its daemon's socket, and without this check every command
/// hung silently instead of failing.
enum Sandbox {
    static let isActive: Bool = {
        typealias Check = @convention(c) (pid_t, UnsafePointer<CChar>?, Int32) -> Int32
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "sandbox_check") else { return false }
        return unsafeBitCast(symbol, to: Check.self)(getpid(), nil, 0) != 0
    }()

    static let error = PeriscopeError.sessionError(reason: """
        periscope cannot run inside a sandbox: it needs the window server and its \
        daemon's socket (~/.periscope/run/sock), and both are denied here. Run it \
        outside the sandbox (in Claude Code: dangerouslyDisableSandbox: true).
        """)
}

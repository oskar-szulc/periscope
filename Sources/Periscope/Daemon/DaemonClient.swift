import Foundation

/// Thin client: send one request, print one response.
///
/// Every path here degrades to in-process execution rather than failing. The
/// daemon is an optimization, never a dependency -- if it cannot be reached or
/// spawned, periscope still works exactly as it did before it existed.
enum DaemonClient {
    /// The argument vector as typed, captured before ArgumentParser consumes it.
    /// The daemon re-parses this so the two sides cannot drift on interpretation.
    static let argumentVector = Array(CommandLine.arguments.dropFirst())

    private static let maxResponseBytes = 64 * 1024 * 1024

    /// Total budget for bringing a daemon up. Spent only on a cold start, and
    /// bounded so that a daemon which cannot start does not tax every command --
    /// the caller falls back in-process once this expires.
    private static let spawnBudget = 1.5

    /// - Returns: the daemon's response, or nil to mean "fall back in-process".
    static func send(globals: GlobalOptions) -> Response? {
        guard let response = roundTrip(request(for: globals)) else { return nil }
        guard response.error?.code == "PROTOCOL_MISMATCH" else { return response }

        // The resident daemon is from an older binary and is shutting itself
        // down. Wait for it to go, then retry once against a fresh one.
        _ = SocketIO.poll(seconds: spawnBudget) {
            !FileManager.default.fileExists(atPath: DaemonPaths.socket.path)
        }
        guard let retry = roundTrip(request(for: globals)),
              retry.error?.code != "PROTOCOL_MISMATCH" else { return nil }
        return retry
    }

    /// Lifecycle request. Unlike a command this never auto-spawns -- asking a
    /// daemon that is not running for its status should say so, not start one.
    static func control(_ verb: ControlVerb) -> DaemonStatusPayload? {
        guard let fd = connect() else { return nil }
        defer { close(fd) }
        return exchange(fd: fd, request: Request(control: verb, arguments: [], workingDirectory: nil, options: nil))?.status
    }

    private static func request(for globals: GlobalOptions) -> Request {
        Request(
            arguments: argumentVector,
            workingDirectory: FileManager.default.currentDirectoryPath,
            options: GlobalOptionsPayload(globals))
    }

    private static func roundTrip(_ request: Request) -> Response? {
        guard let fd = connectOrSpawn() else { return nil }
        defer { close(fd) }
        return exchange(fd: fd, request: request)
    }

    private static func exchange(fd: Int32, request: Request) -> Response? {
        guard let encoded = try? JSONEncoder().encode(request),
              SocketIO.writeAll(fd: fd, data: encoded + Data("\n".utf8)),
              let payload = SocketIO.readMessage(fd: fd, maxBytes: maxResponseBytes)
        else { return nil }
        return try? JSONDecoder().decode(Response.self, from: payload)
    }

    // MARK: - Connect / spawn

    private static func connect() -> Int32? {
        SocketIO.connect(to: DaemonPaths.socket.path, clearIfDead: true)
    }

    private static func connectOrSpawn() -> Int32? {
        if let fd = connect() { return fd }
        // A daemon spawned from inside a sandbox inherits it and hangs.
        guard !Sandbox.isActive, spawnDaemon() else { return nil }

        var fd: Int32?
        _ = SocketIO.poll(seconds: spawnBudget) {
            fd = connect()
            return fd != nil
        }
        return fd
    }

    /// Spawn under an exclusive lock so N parallel invocations start one daemon,
    /// not N. A holder that loses the race waits for the winner's socket instead.
    private static func spawnDaemon() -> Bool {
        try? DaemonPaths.ensureRunDirectory()
        let lockFD = open(DaemonPaths.lock.path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { return false }
        defer { close(lockFD) }

        if flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
            // Someone else is spawning. Their socket is what we want.
            return SocketIO.poll(seconds: spawnBudget) { socketExists }
        }
        defer { flock(lockFD, LOCK_UN) }

        // Re-check under the lock: the winner may have finished while we waited.
        if socketExists { return true }

        let process = Process()
        // Not argv[0]: run from PATH it is the bare name "periscope", which
        // resolves against the cwd, fails to launch, and silently leaves every
        // command running in-process with a freshly reloaded page.
        guard let executable = Bundle.main.executableURL else { return false }
        process.executableURL = executable
        process.arguments = ["serve"]
        // Kept for `daemon log`: WebKit and the daemon report crashes on stderr.
        // Truncated past 1 MB at each spawn rather than rotated.
        let logPath = DaemonPaths.log.path
        if let size = try? FileManager.default.attributesOfItem(atPath: logPath)[.size] as? Int, size > 1 << 20 {
            try? FileManager.default.removeItem(atPath: logPath)
        }
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        let log = FileHandle(forWritingAtPath: logPath)
        log?.seekToEndOfFile()
        process.standardOutput = log ?? FileHandle.nullDevice
        process.standardError = log ?? FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }

        // Hold the lock until the socket exists. Releasing at spawn time leaves a
        // window where the next contender sees no socket and starts a second
        // daemon -- which is how twenty parallel invocations became three.
        return SocketIO.poll(seconds: spawnBudget) { socketExists }
    }

    private static var socketExists: Bool {
        FileManager.default.fileExists(atPath: DaemonPaths.socket.path)
    }
}

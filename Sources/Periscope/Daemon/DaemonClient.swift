import Foundation

/// Thin client: send one request, print one response.
///
/// Every path here degrades to in-process execution rather than failing. The
/// daemon is an optimization, never a dependency — if it cannot be reached or
/// spawned, periscope still works exactly as it did before it existed.
enum DaemonClient {
    /// The argument vector as typed, captured before ArgumentParser consumes it.
    /// The daemon re-parses this so the two sides cannot drift on interpretation.
    static let argumentVector = Array(CommandLine.arguments.dropFirst())

    /// - Returns: the daemon's response, or nil to mean "fall back in-process".
    static func send(globals: GlobalOptions) -> Response? {
        guard let fd = connectOrSpawn() else { return nil }
        defer { close(fd) }

        let request = Request(
            arguments: argumentVector, options: GlobalOptionsPayload(globals))
        guard let data = try? JSONEncoder().encode(request) else { return nil }

        guard writeAll(fd: fd, data: data + Data("\n".utf8)),
              let line = readLine(fd: fd),
              let response = try? JSONDecoder().decode(Response.self, from: Data(line.utf8))
        else { return nil }

        if response.error?.code == "PROTOCOL_MISMATCH" {
            // The resident daemon is from an older binary and is now shutting
            // itself down. Wait for it to go, then retry once against a fresh one.
            return retryAfterVersionSkew(globals: globals)
        }
        return response
    }

    private static func retryAfterVersionSkew(globals: GlobalOptions) -> Response? {
        for _ in 0..<50 {
            if !FileManager.default.fileExists(atPath: DaemonPaths.socket.path) { break }
            usleep(100_000)
        }
        guard let fd = connectOrSpawn() else { return nil }
        defer { close(fd) }

        let request = Request(
            arguments: argumentVector, options: GlobalOptionsPayload(globals))
        guard let data = try? JSONEncoder().encode(request),
              writeAll(fd: fd, data: data + Data("\n".utf8)),
              let line = readLine(fd: fd),
              let response = try? JSONDecoder().decode(Response.self, from: Data(line.utf8)),
              response.error?.code != "PROTOCOL_MISMATCH"
        else { return nil }
        return response
    }

    /// Lifecycle request. Unlike a command, this never auto-spawns -- asking a
    /// daemon that is not running for its status should say so, not start one.
    static func control(_ verb: ControlVerb) -> DaemonStatusPayload? {
        guard let fd = connect() else { return nil }
        defer { close(fd) }

        let request = Request(
            control: verb, arguments: [],
            options: .controlDefault)
        guard let data = try? JSONEncoder().encode(request),
              writeAll(fd: fd, data: data + Data("\n".utf8)),
              let line = readLine(fd: fd),
              let response = try? JSONDecoder().decode(Response.self, from: Data(line.utf8))
        else { return nil }
        return response.status
    }

    // MARK: - Connect / spawn

    private static func connectOrSpawn() -> Int32? {
        if let fd = connect() { return fd }
        guard spawnDaemon() else { return nil }
        for _ in 0..<50 {
            usleep(100_000)
            if let fd = connect() { return fd }
        }
        return nil
    }

    static func connect() -> Int32? {
        let path = DaemonPaths.socket.path
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { close(fd); return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { src in
                ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                    _ = strcpy(dst, src)
                }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, size)
            }
        }
        if ok != 0 {
            close(fd)
            // Nothing is listening: the file is a leftover from a crashed daemon.
            unlink(path)
            return nil
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
            for _ in 0..<50 {
                usleep(100_000)
                if FileManager.default.fileExists(atPath: DaemonPaths.socket.path) { return true }
            }
            return false
        }
        defer { flock(lockFD, LOCK_UN) }

        // Re-check under the lock: the winner may have finished while we waited.
        if FileManager.default.fileExists(atPath: DaemonPaths.socket.path) { return true }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }

        // Hold the lock until the socket actually exists. Releasing at spawn time
        // leaves a window where the next contender sees no socket and spawns a
        // second daemon -- which is how ten parallel invocations became three.
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: DaemonPaths.socket.path) { return true }
            usleep(100_000)
        }
        return false
    }

    // MARK: - I/O

    private static func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    private static func readLine(fd: Int32) -> String? {
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let n = read(fd, &byte, 1)
            if n <= 0 { break }
            if byte == UInt8(ascii: "\n") { break }
            buffer.append(byte)
            if buffer.count > 64 * 1024 * 1024 { return nil }
        }
        return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
    }
}

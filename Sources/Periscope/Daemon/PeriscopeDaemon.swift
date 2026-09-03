import Foundation
import ArgumentParser
import AppKit

/// Accepts commands on a unix socket and runs them against live sessions.
///
/// Framing is newline-delimited JSON, one request per connection: the client
/// writes a line, reads a line, closes. Deliberately the dumbest thing that
/// works — concurrency comes from accepting many connections, not from
/// multiplexing one. Nothing binary crosses the wire; `screenshot` already
/// takes a destination path and writes it daemon-side.
final class PeriscopeDaemon: @unchecked Sendable {
    private let registry: SessionRegistry
    private let acceptQueue = DispatchQueue(label: "periscope.daemon.accept")
    private let workQueue = DispatchQueue(
        label: "periscope.daemon.work", attributes: .concurrent)
    private var listenFD: Int32 = -1
    private let idleExit: TimeInterval
    private var lastActivity = Date()
    private let startedAt = Date()
    private let activityLock = NSLock()

    init(capacity: Int = 8, idleTimeout: TimeInterval = 30 * 60,
         idleExit: TimeInterval = 10 * 60) {
        self.registry = SessionRegistry(capacity: capacity, idleTimeout: idleTimeout)
        self.idleExit = idleExit
    }

    // MARK: - Lifecycle

    func start() throws {
        try DaemonPaths.ensureRunDirectory()
        let path = DaemonPaths.socket.path

        // Stand down if a live daemon already owns this socket -- unlinking
        // unconditionally would steal it and leave two daemons fighting. A socket
        // that refuses a connection is a leftover from a crash and is safe to clear.
        if Self.isSocketLive(path) {
            throw PeriscopeError.sessionError(reason: "daemon already running at \(path)")
        }
        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw PeriscopeError.sessionError(reason: "socket() failed: \(errno)")
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else {
            throw PeriscopeError.sessionError(reason: "socket path too long: \(path)")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { src in
                ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                    _ = strcpy(dst, src)
                }
            }
        }

        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) }
        }
        guard bound == 0 else {
            close(listenFD)
            throw PeriscopeError.sessionError(reason: "bind() failed: \(errno)")
        }

        // Owner-only: the filesystem is the authentication boundary.
        chmod(path, 0o600)

        guard listen(listenFD, 64) == 0 else {
            close(listenFD)
            throw PeriscopeError.sessionError(reason: "listen() failed: \(errno)")
        }

        acceptQueue.async { [weak self] in self?.acceptLoop() }
        scheduleMaintenance()
    }

    /// Connect-probe: the only reliable way to tell a live daemon from the socket
    /// file a crashed one left behind.
    static func isSocketLive(_ path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard path.utf8.count < maxLen else { return false }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { src in
                ptr.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                    _ = strcpy(dst, src)
                }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, size) == 0
            }
        }
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            noteActivity()
            workQueue.async { [weak self] in
                self?.handle(clientFD: clientFD)
            }
        }
    }

    private func noteActivity() {
        activityLock.lock()
        lastActivity = Date()
        activityLock.unlock()
    }

    /// Synchronous so the lock is never held across a suspension point.
    private func idleSeconds() -> TimeInterval {
        activityLock.lock()
        defer { activityLock.unlock() }
        return Date().timeIntervalSince(lastActivity)
    }

    /// Age out idle sessions, and exit entirely once nobody is using us — a daemon
    /// nobody needs should not stay resident.
    private func scheduleMaintenance() {
        acceptQueue.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self else { return }
            Task {
                await self.registry.evictIdle()
                if self.idleSeconds() > self.idleExit, await self.registry.isEmpty {
                    await self.shutdown()
                    await MainActor.run { NSApp.terminate(nil) }
                    return
                }
                self.scheduleMaintenance()
            }
        }
    }

    func shutdown() async {
        await registry.shutdownAll()
        if listenFD >= 0 { close(listenFD) }
        unlink(DaemonPaths.socket.path)
    }

    // MARK: - Connection handling

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }
        guard let line = readLine(fd: clientFD) else { return }

        let response: Response
        do {
            let request = try JSONDecoder().decode(Request.self, from: Data(line.utf8))
            response = executeSynchronously(request)
        } catch {
            response = .failure(ErrorPayload(
                code: "BAD_REQUEST",
                message: "could not decode request: \(error)",
                exitCode: 4))
        }

        if let data = try? JSONEncoder().encode(response) {
            write(fd: clientFD, data: data + Data("\n".utf8))
        }
    }

    /// Bridges the socket thread (blocking) to the actor/MainActor world (async).
    /// Blocking here is safe: this runs on a concurrent worker queue, never on the
    /// main thread, which is where WebKit actually does its work.
    private func executeSynchronously(_ request: Request) -> Response {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox()

        Task {
            box.value = await execute(request)
            semaphore.signal()
        }

        let deadline = DispatchTime.now() + .seconds(max(request.options.timeout + 5, 10))
        if semaphore.wait(timeout: deadline) == .timedOut {
            return .failure(ErrorPayload(
                code: "TIMEOUT",
                message: "Operation timed out after \(request.options.timeout)s",
                exitCode: 2))
        }
        return box.value ?? .failure(ErrorPayload(
            code: "INTERNAL", message: "no response produced", exitCode: 1))
    }

    private func execute(_ request: Request) async -> Response {
        guard request.protocolVersion == periscopeProtocolVersion else {
            // Version skew after a rebuild. Refuse, then exit so the client's
            // respawn brings up a daemon matching the new binary.
            Task {
                await self.shutdown()
                await MainActor.run { NSApp.terminate(nil) }
            }
            return .failure(ErrorPayload(
                code: "PROTOCOL_MISMATCH",
                message: "daemon speaks protocol \(periscopeProtocolVersion), "
                    + "client speaks \(request.protocolVersion)",
                exitCode: 4))
        }

        if let verb = request.control {
            return await handleControl(verb)
        }

        // Re-parse with ArgumentParser rather than trusting a pre-parsed payload,
        // so client and daemon cannot drift on how a command is interpreted.
        let block: CommandRunner.CommandBlock
        do {
            block = try Self.resolveBlock(arguments: request.arguments)
        } catch let error as PeriscopeError {
            return .failure(ErrorPayload(error))
        } catch {
            return .failure(ErrorPayload(
                code: "ARGUMENT_ERROR", message: "\(error)", exitCode: 4))
        }

        let options = request.options
        let session: LiveSession
        if options.noSession {
            session = await registry.ephemeralSession(viewport: options.viewportSize)
        } else {
            session = await registry.session(
                named: options.session, viewport: options.viewportSize)
        }

        var warnings = await session.drainWarnings()

        do {
            let result = try await session.run(verbose: options.verbose, block)
            if options.noSession { await session.shutdown() }
            return .ok(result, warnings: warnings)
        } catch let error as PeriscopeError {
            if options.noSession { await session.shutdown() }
            return .failure(ErrorPayload(error), warnings: warnings)
        } catch {
            if options.noSession { await session.shutdown() }
            warnings.append("unexpected error: \(error)")
            return .failure(ErrorPayload(
                code: "INTERNAL", message: error.localizedDescription, exitCode: 1),
                warnings: warnings)
        }
    }

    private func handleControl(_ verb: ControlVerb) async -> Response {
        let now = Date()
        let sessions = await registry.info().map {
            SessionInfoPayload(
                name: $0.name, idleSeconds: Int(now.timeIntervalSince($0.lastUsed)))
        }
        let payload = DaemonStatusPayload(
            pid: ProcessInfo.processInfo.processIdentifier,
            uptimeSeconds: Int(now.timeIntervalSince(startedAt)),
            protocolVersion: periscopeProtocolVersion,
            sessions: sessions)

        if verb == .stop {
            // Reply first, then exit -- the client needs the response before we go.
            Task {
                try? await Task.sleep(for: .milliseconds(150))
                await self.shutdown()
                await MainActor.run { NSApp.terminate(nil) }
            }
        }
        return .status(payload)
    }

    /// Runs a subcommand's synchronous `run()` with the daemon interception active,
    /// which captures its command block instead of executing it in-process.
    private static func resolveBlock(arguments: [String]) throws -> CommandRunner.CommandBlock {
        let execution = DaemonExecution()
        CommandRunner.daemonExecution = execution
        defer { CommandRunner.daemonExecution = nil }

        var command = try PeriscopeRoot.parseAsRoot(arguments)
        try command.run()

        guard let block = execution.block else {
            throw PeriscopeError.argumentError(
                reason: "command '\(arguments.first ?? "")' produced no work")
        }
        return block
    }

    // MARK: - Socket I/O

    private func readLine(fd: Int32) -> String? {
        var buffer = Data()
        var byte: UInt8 = 0
        while true {
            let n = read(fd, &byte, 1)
            if n <= 0 { break }
            if byte == UInt8(ascii: "\n") { break }
            buffer.append(byte)
            if buffer.count > 8 * 1024 * 1024 { return nil }
        }
        return buffer.isEmpty ? nil : String(data: buffer, encoding: .utf8)
    }

    private func write(fd: Int32, data: Data) {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Foundation.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { return }
                offset += n
            }
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    var value: Response?
}

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
    private static let maxRequestBytes = 8 * 1024 * 1024

    private let registry: SessionRegistry
    private let acceptQueue = DispatchQueue(label: "periscope.daemon.accept")
    /// Maintenance runs on its own queue, never on `acceptQueue`: the accept loop
    /// blocks forever in `accept()`, so a timer scheduled on that serial queue
    /// would queue behind it and never fire — which is exactly how idle eviction
    /// and idle-exit silently stopped working (sessions lived for days).
    private let maintenanceQueue = DispatchQueue(label: "periscope.daemon.maintenance")
    private var maintenanceTimer: DispatchSourceTimer?
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
        if SocketIO.connect(to: path) != nil {
            throw PeriscopeError.sessionError(reason: "daemon already running at \(path)")
        }
        unlink(path)

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else {
            throw PeriscopeError.sessionError(reason: "socket() failed: \(errno)")
        }

        guard var addr = SocketIO.address(for: path) else {
            close(listenFD)
            throw PeriscopeError.sessionError(reason: "socket path too long: \(path)")
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
        startMaintenance()
    }

    private func acceptLoop() {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                if errno == EINTR { continue }
                break
            }
            noteActivity()
            Task { [weak self] in
                await self?.handle(clientFD: clientFD)
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

    /// Age out idle sessions every 60s, and exit entirely once nobody is using us
    /// — a daemon nobody needs should not stay resident. A repeating
    /// `DispatchSourceTimer` on `maintenanceQueue` fires independently of the
    /// blocked accept loop.
    private func startMaintenance() {
        let timer = DispatchSource.makeTimerSource(queue: maintenanceQueue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.registry.evictIdle()
                if self.idleSeconds() > self.idleExit, await self.registry.isEmpty {
                    self.maintenanceTimer?.cancel()
                    await self.shutdown()
                    await MainActor.run { NSApp.terminate(nil) }
                }
            }
        }
        maintenanceTimer = timer
        timer.resume()
    }

    func shutdown() async {
        await registry.shutdownAll()
        if listenFD >= 0 { close(listenFD) }
        unlink(DaemonPaths.socket.path)
    }

    // MARK: - Connection handling

    private func handle(clientFD: Int32) async {
        defer { close(clientFD) }
        guard let payload = SocketIO.readMessage(fd: clientFD, maxBytes: Self.maxRequestBytes)
        else { return }

        let response: Response
        do {
            response = await execute(try JSONDecoder().decode(Request.self, from: payload))
        } catch {
            response = .failure(ErrorPayload(
                code: "BAD_REQUEST",
                message: "could not decode request: \(error)",
                exitCode: 4))
        }

        if let data = try? JSONEncoder().encode(response) {
            SocketIO.writeAll(fd: clientFD, data: data + Data("\n".utf8))
        }
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
            block = try Self.resolveBlock(
                arguments: request.arguments, workingDirectory: request.workingDirectory)
        } catch let error as PeriscopeError {
            return .failure(ErrorPayload(error))
        } catch {
            return .failure(ErrorPayload(
                code: "ARGUMENT_ERROR", message: "\(error)", exitCode: 4))
        }

        guard let options = request.options else {
            return .failure(ErrorPayload(
                code: "BAD_REQUEST", message: "command request carries no options",
                exitCode: 4))
        }
        let session: LiveSession
        if options.noSession {
            session = await registry.ephemeralSession(viewport: options.viewportSize)
        } else {
            session = await registry.session(
                named: options.session, viewport: options.viewportSize)
        }

        var warnings = await session.drainWarnings()

        let response: Response
        do {
            let result = try await withTimeout(seconds: options.timeout) {
                try await session.run(verbose: options.verbose, block)
            }
            response = .ok(result, warnings: warnings + (await session.drainWarnings()))
        } catch let error as PeriscopeError {
            if case .timeout = error {
                warnings.append("Page at timeout: \(await session.locationDescription())")
                if !options.noSession {
                    await registry.discard(session)
                    warnings.append("Session '\(options.session)' was reset so the next command does not wait on this one; it restarts from its last saved state, so navigate again before reading.")
                }
            }
            response = .failure(ErrorPayload(error), warnings: warnings)
        } catch {
            warnings.append("unexpected error: \(error)")
            response = .failure(
                ErrorPayload(code: "INTERNAL", message: error.localizedDescription, exitCode: 1),
                warnings: warnings)
        }

        if options.noSession { await registry.release(session) }
        return response
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
    private static func resolveBlock(
        arguments: [String], workingDirectory: String?
    ) throws -> CommandRunner.CommandBlock {
        let execution = DaemonExecution(workingDirectory: workingDirectory)
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

}

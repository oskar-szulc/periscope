import AppKit
import Foundation

enum CommandRunner {
    typealias CommandBlock = @MainActor @Sendable (BrowserEngine) async throws -> CommandResult

    /// Set by the daemon while it executes a re-parsed command in-process.
    ///
    /// Every one of the 28 subcommands funnels through `run`, so intercepting here
    /// means the daemon can reuse them verbatim — no command file knows transport
    /// exists. Thread-local rather than global because the daemon handles each
    /// connection on its own thread.
    static var daemonExecution: DaemonExecution? {
        get { Thread.current.threadDictionary["periscope.daemonExecution"] as? DaemonExecution }
        set { Thread.current.threadDictionary["periscope.daemonExecution"] = newValue }
    }

    /// Resolve a user-supplied path against the directory the *client* ran in.
    ///
    /// A command's own `FileManager` sees the daemon's working directory, which is
    /// wherever it happened to be spawned -- so `screenshot shot.png` would write
    /// to some unrelated directory and report success. Any command that touches
    /// the filesystem must route its path through here.
    static func resolvePath(_ path: String) -> String {
        guard let base = daemonExecution?.workingDirectory else { return path }
        return URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: base)).path
    }

    static func run(globals: GlobalOptions, command original: @escaping CommandBlock) {
        // Browser settings a command asks for (--user-agent, --resource-mode)
        // apply here, on both paths: the daemon re-parses argv, so its copy of
        // `globals` is the client's.
        let (userAgent, resourceMode) = (globals.userAgent, globals.resourceMode)
        let command: CommandBlock = { engine in
            await engine.configure(userAgent: userAgent, resourceMode: resourceMode)
            return try await original(engine)
        }

        // Inside the daemon: hand the block over instead of running it.
        if let execution = daemonExecution {
            execution.block = command
            return
        }

        // The daemon keeps the page alive between commands, which is the whole
        // reason it exists. If it is unreachable we run in-process instead --
        // slower, but identical behavior, so no user is ever blocked by it.
        if !globals.noDaemon, let response = DaemonClient.send(globals: globals) {
            emitResponse(response, globals: globals)
            return
        }

        runInProcess(globals: globals, command: command)
    }

    /// Print a daemon response exactly as in-process execution would have.
    private static func emitResponse(_ response: Response, globals: GlobalOptions) {
        let formatter = makeFormatter(json: globals.json, fields: globals.fields)

        for warning in response.warnings {
            FileHandle.standardError.write(Data((warning + "\n").utf8))
        }

        if let error = response.error {
            emit(error, formatter: formatter, globals: globals)
            Foundation.exit(error.exitCode)
        }
        if let result = response.result {
            print(formatter.format(result))
        }
    }

    /// One-shot execution: boot an app, build an engine, restore, run, save, exit.
    /// Still the fallback whenever the daemon is unavailable or `--no-daemon` is set.
    static func runInProcess(globals: GlobalOptions, command: @escaping CommandBlock) {
        let formatter = makeFormatter(json: globals.json, fields: globals.fields)
        let (width, height) = globals.viewportSize

        MainActor.assumeIsolated {
            AppRunner.run(json: globals.json) {
                let engine = await MainActor.run {
                    let e = BrowserEngine(viewportWidth: width, viewportHeight: height)
                    e.verbose = globals.verbose
                    return e
                }

                do {
                    if !globals.noSession {
                        if let warning = try await SessionRestore.restore(
                            engine: engine, session: globals.session)
                        {
                            FileHandle.standardError.write(Data((warning + "\n").utf8))
                        }
                    }

                    let result = try await withTimeout(seconds: globals.timeout) {
                        try await command(engine)
                    }

                    if !globals.noSession {
                        try await SessionRestore.save(engine: engine, session: globals.session)
                    }

                    print(formatter.format(result))
                    await MainActor.run { engine.close() }
                } catch let error as PeriscopeError {
                    if case .timeout = error {
                        let at = await MainActor.run { engine.locationDescription }
                        FileHandle.standardError.write(Data("Page at timeout: \(at)\n".utf8))
                    }
                    emit(ErrorPayload(error), formatter: formatter, globals: globals)
                    await MainActor.run { engine.close() }
                    Foundation.exit(error.exitCode)
                } catch {
                    emit(
                        ErrorPayload(
                            code: "INTERNAL",
                            message: error.localizedDescription, exitCode: 1),
                        formatter: formatter, globals: globals)
                    await MainActor.run { engine.close() }
                    Foundation.exit(1)
                }
            }
        }
    }

    private static func emit(_ payload: ErrorPayload, formatter: OutputFormatting, globals: GlobalOptions) {
        let output = formatter.formatError(payload)
        if globals.json {
            print(output)
        } else {
            FileHandle.standardError.write(Data((output + "\n").utf8))
        }
    }
}

/// Carries a command block out of a subcommand's synchronous `run()` so the
/// daemon can execute it against a live session instead of a fresh engine.
final class DaemonExecution: @unchecked Sendable {
    var block: CommandRunner.CommandBlock?
    /// The client's working directory, for `CommandRunner.resolvePath`.
    let workingDirectory: String?

    init(workingDirectory: String?) {
        self.workingDirectory = workingDirectory
    }
}

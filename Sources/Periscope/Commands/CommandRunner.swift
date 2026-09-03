import Foundation
import AppKit

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

    static func run(globals: GlobalOptions, command: @escaping CommandBlock) {
        // Inside the daemon: hand the block over instead of running it.
        if let execution = daemonExecution {
            execution.capture(command)
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
        let formatter = makeFormatter(json: globals.json)

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
        let formatter = makeFormatter(json: globals.json)
        let (width, height) = globals.viewportSize

        MainActor.assumeIsolated {
            AppRunner.run {
                let engine = await MainActor.run {
                    let e = BrowserEngine(viewportWidth: width, viewportHeight: height)
                    e.verbose = globals.verbose
                    return e
                }

                do {
                    if !globals.noSession {
                        if let warning = try await SessionRestore.restore(
                            engine: engine, session: globals.session) {
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
                    emit(ErrorPayload(error), formatter: formatter, globals: globals)
                    await MainActor.run { engine.close() }
                    Foundation.exit(error.exitCode)
                } catch {
                    emit(ErrorPayload(code: "INTERNAL",
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
    private(set) var block: CommandRunner.CommandBlock?

    func capture(_ block: @escaping CommandRunner.CommandBlock) {
        self.block = block
    }
}

import ArgumentParser
import Foundation
import AppKit

struct Serve: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the session daemon in the foreground")

    @Option(name: .long, help: "Max live sessions before LRU eviction")
    var capacity: Int = 8

    @Option(name: .long, help: "Evict a session after this many seconds idle")
    var idleTimeout: Int = 30 * 60

    @Option(name: .long, help: "Exit after this many seconds with no sessions and no traffic")
    var idleExit: Int = 10 * 60

    func run() throws {
        let daemon = PeriscopeDaemon(
            capacity: capacity,
            idleTimeout: TimeInterval(idleTimeout),
            idleExit: TimeInterval(idleExit))

        // WebKit needs a live NSApplication run loop. Unlike a one-shot command,
        // this one never terminates itself — the daemon owns the process.
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            do {
                try daemon.start()
            } catch {
                FileHandle.standardError.write(Data("periscope serve: \(error)\n".utf8))
                Foundation.exit(1)
            }
            FileHandle.standardError.write(
                Data("periscope daemon listening at \(DaemonPaths.socket.path)\n".utf8))
            app.run()
        }
    }
}

struct DaemonGroup: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "Inspect or stop the session daemon",
        subcommands: [DaemonStatus.self, DaemonStop.self])
}

struct DaemonStatus: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status", abstract: "Show daemon status and live sessions")

    @Flag(name: .long, help: "Output as JSON") var json: Bool = false

    func run() throws {
        guard let status = DaemonClient.control(.status) else {
            if Sandbox.isActive { throw Sandbox.error }
            print(json ? #"{"running":false}"# : "daemon: not running")
            return
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(status), let text = String(data: data, encoding: .utf8) {
                print(text)
            }
            return
        }

        print("daemon: running (pid \(status.pid), up \(format(status.uptimeSeconds)), "
              + "protocol \(status.protocolVersion))")
        if status.sessions.isEmpty {
            print("sessions: none live")
        } else {
            print("sessions: \(status.sessions.count) live")
            for session in status.sessions {
                print("  \(session.name)  idle \(format(session.idleSeconds))")
            }
        }
    }

    private func format(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h\((seconds % 3600) / 60)m"
    }
}

struct DaemonStop: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop", abstract: "Stop the daemon, flushing sessions to disk")

    func run() throws {
        guard let status = DaemonClient.control(.stop) else {
            print("daemon: not running")
            return
        }
        print("daemon: stopping (pid \(status.pid)), "
              + "\(status.sessions.count) session(s) flushed to disk")
    }
}

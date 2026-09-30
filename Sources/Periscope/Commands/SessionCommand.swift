import ArgumentParser
import Foundation

struct Session: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage sessions",
        subcommands: [SessionList.self, SessionDelete.self, SessionExport.self, SessionImport.self])
}

struct SessionList: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List saved sessions")
    @OptionGroup var globals: GlobalOptions
    func run() throws {
        // Saved and live: a session used only since the daemon started has no
        // saved copy yet. Ephemeral --no-session browsers are not sessions.
        let live = DaemonClient.control(.status)?.sessions.map(\.name).filter { !$0.hasPrefix("(") } ?? []
        let sessions = Set(try SessionManager().listSessions() + live).sorted()
        print(makeFormatter(json: globals.json, fields: globals.fields).format(.sessionList(sessions)))
    }
}

struct SessionDelete: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a session")
    @Argument(help: "Session name") var name: String
    func run() throws {
        // The live page first, or the daemon would save it back on eviction.
        let live = DaemonClient.control(.status)?.sessions.contains { $0.name == name } ?? false
        if live { _ = DaemonClient.control(.close, arguments: [name]) }
        do {
            try SessionManager().deleteSession(name)
        } catch PeriscopeError.sessionError where live {
            // Live only: nothing was saved yet, and closing it was the whole delete.
        }
        print("Deleted session: \(name)")
    }
}

struct SessionExport: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export", abstract: "Export a session")
    @Argument(help: "Session name") var name: String
    @Argument(help: "Export path") var path: String?
    func run() throws {
        let dest = URL(fileURLWithPath: path ?? "\(name)-session-export")
        try SessionManager().exportSession(name, to: dest)
        print("Exported session '\(name)' to \(dest.path)")
    }
}

struct SessionImport: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "import", abstract: "Import a session")
    @Argument(help: "Session name") var name: String
    @Argument(help: "Import path") var path: String
    func run() throws {
        try SessionManager().importSession(name, from: URL(fileURLWithPath: path))
        print("Imported session '\(name)' from \(path)")
    }
}

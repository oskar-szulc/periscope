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
        let sessions = try SessionManager().listSessions().sorted()
        print(makeFormatter(json: globals.json, fields: globals.fields).format(.sessionList(sessions)))
    }
}

struct SessionDelete: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a session")
    @Argument(help: "Session name") var name: String
    func run() throws {
        try SessionManager().deleteSession(name)
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

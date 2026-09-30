import Foundation

/// Older snapshots also carry title, viewport, timestamp and origin; nothing
/// read them back, and decoding ignores them.
struct SessionState: Codable {
    let url: String
}

struct PersistedStorage: Codable {
    let localStorage: [String: String]
}

struct SessionManager {
    var baseDir = DaemonPaths.base.appendingPathComponent("sessions")

    private func sessionDir(_ name: String) -> URL {
        baseDir.appendingPathComponent(name)
    }

    /// One JSON file of a session's snapshot: state.json, cookies.json or storage.json.
    func write(_ value: some Encodable, _ file: String, session: String) throws {
        let dir = sessionDir(session)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: dir.appendingPathComponent(file))
    }

    func read<T: Decodable>(_ type: T.Type, _ file: String, session: String) throws -> T? {
        let url = sessionDir(session).appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    func listSessions() throws -> [String] {
        guard FileManager.default.fileExists(atPath: baseDir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: baseDir.path)
            .filter { name in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(
                    atPath: sessionDir(name).path, isDirectory: &isDir) && isDir.boolValue
            }
    }

    func deleteSession(_ name: String) throws {
        let dir = sessionDir(name)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw PeriscopeError.sessionError(reason: "Session '\(name)' not found")
        }
        try FileManager.default.removeItem(at: dir)
    }

    func exportSession(_ name: String, to path: URL) throws {
        let dir = sessionDir(name)
        guard FileManager.default.fileExists(atPath: dir.path) else {
            throw PeriscopeError.sessionError(reason: "Session '\(name)' not found")
        }
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        try FileManager.default.copyItem(at: dir, to: path)
    }

    func importSession(_ name: String, from path: URL) throws {
        let dir = sessionDir(name)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.copyItem(at: path, to: dir)
    }
}

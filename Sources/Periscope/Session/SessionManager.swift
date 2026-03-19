import Foundation

struct SessionState: Codable {
    let url: String
    let title: String?
    let viewport: String
    var timestamp: String?
}

struct PersistedStorage: Codable {
    let origin: String
    let localStorage: [String: String]
}

struct SessionManager {
    let baseDir: URL

    init(baseDir: URL? = nil) {
        if let baseDir {
            self.baseDir = baseDir
        } else {
            self.baseDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".periscope/sessions")
        }
    }

    private func sessionDir(_ name: String) -> URL {
        baseDir.appendingPathComponent(name)
    }

    func saveState(_ state: SessionState, session: String) throws {
        let dir = sessionDir(session)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var s = state
        s.timestamp = ISO8601DateFormatter().string(from: Date())
        let data = try JSONEncoder().encode(s)
        try data.write(to: dir.appendingPathComponent("state.json"))
    }

    func loadState(session: String) throws -> SessionState? {
        let file = sessionDir(session).appendingPathComponent("state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(SessionState.self, from: Data(contentsOf: file))
    }

    func saveCookies(_ cookies: [PersistedCookie], session: String) throws {
        let dir = sessionDir(session)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try CookieStore.serialize(CookieStore.pruneExpired(cookies))
        try data.write(to: dir.appendingPathComponent("cookies.json"))
    }

    func loadCookies(session: String) throws -> [PersistedCookie] {
        let file = sessionDir(session).appendingPathComponent("cookies.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try CookieStore.deserialize(Data(contentsOf: file))
    }

    func saveStorage(_ storage: PersistedStorage, session: String) throws {
        let dir = sessionDir(session)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(storage).write(to: dir.appendingPathComponent("storage.json"))
    }

    func loadStorage(session: String) throws -> PersistedStorage? {
        let file = sessionDir(session).appendingPathComponent("storage.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(PersistedStorage.self, from: Data(contentsOf: file))
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

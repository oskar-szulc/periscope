import Foundation

/// The live sessions the daemon is holding open.
///
/// Bounded on two axes because each `LiveSession` owns a WebKit content process:
/// idle sessions age out, and the total is capped with LRU eviction. Eviction is
/// not data loss — the session is flushed to disk and cold-starts on next use.
actor SessionRegistry {
    struct Info: Sendable {
        let name: String
        let lastUsed: Date
    }

    private var sessions: [String: LiveSession] = [:]
    private let capacity: Int
    private let idleTimeout: TimeInterval
    private let viewport: (width: Int, height: Int)

    init(capacity: Int = 8, idleTimeout: TimeInterval = 30 * 60,
         viewport: (width: Int, height: Int) = (1920, 1080)) {
        self.capacity = capacity
        self.idleTimeout = idleTimeout
        self.viewport = viewport
    }

    /// Warm path: hand back the live session. Cold path: build one and replay the
    /// snapshot into it, once.
    func session(named name: String, viewport: (width: Int, height: Int)) async -> LiveSession {
        if let existing = sessions[name] { return existing }

        await evictIfNeeded(making: 1)
        let session = await LiveSession(
            name: name, viewportWidth: viewport.width, viewportHeight: viewport.height)
        sessions[name] = session
        await session.restoreFromDisk()
        return session
    }

    /// `--no-session`: an engine with no disk identity, torn down after the command.
    func ephemeralSession(viewport: (width: Int, height: Int)) async -> LiveSession {
        await LiveSession(
            name: "(ephemeral)", viewportWidth: viewport.width,
            viewportHeight: viewport.height, ephemeral: true)
    }

    func evictIdle() async {
        let cutoff = Date().addingTimeInterval(-idleTimeout)
        for (name, session) in sessions where await session.lastUsed < cutoff {
            await session.shutdown()
            sessions[name] = nil
        }
    }

    private func evictIfNeeded(making room: Int) async {
        while sessions.count + room > capacity {
            var oldestName: String?
            var oldestDate = Date.distantFuture
            for (name, session) in sessions {
                let used = await session.lastUsed
                if used < oldestDate {
                    oldestDate = used
                    oldestName = name
                }
            }
            guard let victim = oldestName, let session = sessions[victim] else { return }
            await session.shutdown()
            sessions[victim] = nil
        }
    }

    var isEmpty: Bool { sessions.isEmpty }

    func info() async -> [Info] {
        var out: [Info] = []
        for (name, session) in sessions {
            out.append(Info(name: name, lastUsed: await session.lastUsed))
        }
        return out.sorted { $0.lastUsed > $1.lastUsed }
    }

    func shutdownAll() async {
        for (_, session) in sessions {
            await session.shutdown()
        }
        sessions.removeAll()
    }
}

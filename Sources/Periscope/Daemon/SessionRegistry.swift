import Foundation

/// The live sessions the daemon is holding open.
///
/// Bounded on two axes because each `LiveSession` owns a WebKit content process:
/// idle sessions age out, and the total is capped with LRU eviction. Eviction is
/// not data loss -- the session is flushed to disk and cold-starts on next use.
actor SessionRegistry {
    private struct Entry {
        let session: LiveSession
        /// Held here rather than read back off the session actor: an eviction scan
        /// that awaits each session suspends mid-scan, and can then observe the
        /// dictionary it is walking mutated underneath it.
        var lastUsed: Date
        let isEphemeral: Bool
    }

    private var entries: [String: Entry] = [:]
    private let capacity: Int
    private let idleTimeout: TimeInterval
    private var ephemeralCounter = 0

    init(capacity: Int, idleTimeout: TimeInterval) {
        self.capacity = capacity
        self.idleTimeout = idleTimeout
    }

    /// Warm path: hand back the live session. Cold path: build one and replay the
    /// snapshot into it, once.
    func session(named name: String, viewport: (width: Int, height: Int)) async -> LiveSession {
        if let existing = entries[name] {
            entries[name]?.lastUsed = Date()
            return existing.session
        }

        await evictOldestIfFull()
        let session = await LiveSession(
            name: name, viewportWidth: viewport.width, viewportHeight: viewport.height)
        entries[name] = Entry(session: session, lastUsed: Date(), isEphemeral: false)
        await session.restoreFromDisk()
        return session
    }

    /// `--no-session`: a browser with no disk identity, discarded after the command.
    ///
    /// Registered like any other session rather than handed out untracked. The
    /// registry is what bounds WebKit content processes, so an unregistered
    /// session would be invisible to the capacity cap and to shutdown -- N
    /// concurrent `--no-session` commands would be N unbounded processes, and the
    /// daemon could decide it was idle and exit while they were still running.
    func ephemeralSession(viewport: (width: Int, height: Int)) async -> LiveSession {
        await evictOldestIfFull()
        ephemeralCounter += 1
        let key = "(ephemeral \(ephemeralCounter))"
        let session = await LiveSession(
            name: key, viewportWidth: viewport.width,
            viewportHeight: viewport.height, ephemeral: true)
        entries[key] = Entry(session: session, lastUsed: Date(), isEphemeral: true)
        return session
    }

    /// Drop an ephemeral session once its command is done. Named sessions ignore
    /// this -- they live until evicted.
    func release(_ session: LiveSession) async {
        let name = session.name
        guard let entry = entries[name], entry.isEphemeral else { return }
        entries[name] = nil
        await entry.session.shutdown()
    }

    /// After a timeout: the abandoned command may hold the session forever (its
    /// lock is released only when it finishes), so every later command would
    /// queue behind it. Drop it without saving, since saving runs JS on the
    /// wedged page; the next command cold-starts from the last snapshot.
    func discard(_ session: LiveSession) async {
        let name = session.name
        guard let entry = entries[name], entry.session === session else { return }
        entries[name] = nil
        await entry.session.abandon()
    }

    /// `session delete`: the page goes with the saved copy, unsaved, or the
    /// daemon would write the session back to disk on its next eviction.
    func close(named name: String) async {
        guard let entry = entries.removeValue(forKey: name) else { return }
        await entry.session.abandon()
    }

    func evictIdle() async {
        let cutoff = Date().addingTimeInterval(-idleTimeout)
        // An ephemeral session belongs to an in-flight command, never to the clock.
        for (name, entry) in entries where !entry.isEphemeral && entry.lastUsed < cutoff {
            entries[name] = nil
            await entry.session.shutdown()
        }
    }

    /// At most one session can be over the line, since the cap is an invariant
    /// every insertion path maintains.
    private func evictOldestIfFull() async {
        guard entries.count >= capacity else { return }
        guard
            let victim =
                entries
                .filter({ !$0.value.isEphemeral })
                .min(by: { $0.value.lastUsed < $1.value.lastUsed })
        else { return }

        entries[victim.key] = nil
        await victim.value.session.shutdown()
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Most recently used first.
    func info() -> [SessionInfoPayload] {
        let now = Date()
        return
            entries
            .sorted { $0.value.lastUsed > $1.value.lastUsed }
            .map { SessionInfoPayload(name: $0.key, idleSeconds: Int(now.timeIntervalSince($0.value.lastUsed))) }
    }

    func shutdownAll() async {
        let live = entries.values.map(\.session)
        entries.removeAll()
        for session in live {
            await session.shutdown()
        }
    }
}

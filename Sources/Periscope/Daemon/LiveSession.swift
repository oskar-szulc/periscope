import Foundation

/// A browser that stays alive between commands.
///
/// This is the whole point of the daemon. A one-shot process has to rebuild the
/// page from a cookie/storage snapshot every time; a `LiveSession` just hands
/// out the engine it already has.
actor LiveSession {
    let name: String
    private let engine: BrowserEngine
    private let lock = AsyncLock()
    private(set) var lastUsed = Date()
    private(set) var isEphemeral: Bool

    /// Warnings raised while restoring, drained by the first command's response.
    private var pendingWarnings: [String] = []

    init(name: String, viewportWidth: Int, viewportHeight: Int, ephemeral: Bool = false) async {
        self.name = name
        self.isEphemeral = ephemeral
        self.engine = await MainActor.run {
            BrowserEngine(viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        }
    }

    /// Cold start: replay the disk snapshot into the fresh page. Runs once per
    /// session, not once per command, and is the only time the snapshot is read.
    func restoreFromDisk() async {
        guard !isEphemeral else { return }
        do {
            if let warning = try await SessionRestore.restore(engine: engine, session: name) {
                pendingWarnings.append(warning)
            }
        } catch {
            pendingWarnings.append("warning: could not restore session '\(name)': \(error)")
        }
    }

    func run(verbose: Bool, _ block: @escaping CommandRunner.CommandBlock) async throws -> CommandResult {
        // The actor alone does not serialize this: `await block(engine)` suspends,
        // and actor reentrancy would let a second command interleave against the
        // same live page. The lock makes ordering well-defined.
        await lock.acquire()
        defer { lock.releaseSync() }

        lastUsed = Date()
        await MainActor.run { engine.verbose = verbose }
        return try await block(engine)
    }

    func drainWarnings() -> [String] {
        defer { pendingWarnings.removeAll() }
        return pendingWarnings
    }

    /// Flush to disk and tear down. Called on eviction and on daemon shutdown —
    /// the snapshot is the durability layer, the live page is the source of truth.
    func shutdown() async {
        if !isEphemeral {
            try? await SessionRestore.save(engine: engine, session: name)
        }
        await MainActor.run { engine.close() }
    }
}

/// Minimal FIFO async lock. Foundation has no async-safe mutex that can be held
/// across a suspension point, and `DispatchSemaphore` would block the cooperative
/// thread pool.
actor AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    nonisolated func releaseSync() {
        Task { await release() }
    }
}

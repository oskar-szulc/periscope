import Foundation

/// A browser that stays alive between commands.
///
/// This is the whole point of the daemon. A one-shot process has to rebuild the
/// page from a cookie/storage snapshot every time; a `LiveSession` just hands
/// out the engine it already has.
actor LiveSession {
    let name: String
    private let engine: BrowserEngine
    private let isEphemeral: Bool

    /// Warnings raised while restoring, drained by the first command's response.
    private var pendingWarnings: [String] = []

    /// A navigation that failed and left the previous page loaded. Until one
    /// succeeds, every read carries a warning: `text` after a failed `navigate`
    /// silently returned the old page, and a studio's listings nearly got
    /// attributed to two others.
    private var failedNavigation: String?

    /// Commands against one session must not interleave. The actor alone does not
    /// give us that: `await block(engine)` suspends, and actor reentrancy would
    /// let a second command run against the same live page mid-flight.
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

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

    func run(verbose: Bool, userAgent: String?, _ block: @escaping CommandRunner.CommandBlock) async throws -> CommandResult {
        await acquire()
        defer { release() }

        await MainActor.run {
            engine.verbose = verbose
            engine.setUserAgent(userAgent)
        }
        let result: CommandResult
        do {
            result = try await block(engine)
        } catch let error as PeriscopeError {
            if case .navigationFailed(let url, _) = error, !url.isEmpty { failedNavigation = url }
            throw error
        }
        if case .navigate = result {
            failedNavigation = nil
        } else if let failedNavigation {
            let current = await MainActor.run { engine.currentURL ?? "(no page)" }
            pendingWarnings.append(
                "warning: the last navigate, to \(failedNavigation), failed; this is still \(current)")
        }
        return result
    }

    /// For timeout messages. Reads the page without taking the session: the
    /// timed-out command may still hold it.
    func locationDescription() async -> String {
        await MainActor.run { engine.locationDescription }
    }

    func drainWarnings() -> [String] {
        defer { pendingWarnings.removeAll() }
        return pendingWarnings
    }

    /// Flush to disk and tear down. Called on eviction and on daemon shutdown --
    /// the snapshot is the durability layer, the live page is the source of truth.
    func shutdown() async {
        if !isEphemeral {
            try? await SessionRestore.save(engine: engine, session: name)
        }
        await MainActor.run { engine.close() }
    }

    // MARK: - Serialization

    private func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Synchronous and actor-isolated, so `defer` can call it directly. Hoisting
    /// this into a separate actor would force a fire-and-forget `Task` here,
    /// since `defer` cannot await a hop to another actor.
    private func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

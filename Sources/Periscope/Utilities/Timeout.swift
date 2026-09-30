import Foundation
import Synchronization

/// Runs `operation`, throwing `PeriscopeError.timeout` if it has not finished
/// after `seconds`. Zero or less means no limit (`--timeout 0`).
///
/// Not a task group: a group waits for every child before returning, so an
/// operation that ignores cancellation (FoundationModels' `respond()` hangs this
/// way) held the caller past its deadline, forever in the worst case. Here the
/// loser is cancelled and abandoned instead; an abandoned operation keeps what
/// it captured alive until it returns.
func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    if seconds <= 0 { return try await operation() }
    let race = Race<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, seconds: seconds, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// First result wins: it resumes the continuation and cancels both tasks.
private final class Race<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, Error>?
        var tasks: [Task<Void, Never>] = []
        var done = false
    }
    private let state = Mutex(State())

    func start(
        _ continuation: CheckedContinuation<T, Error>, seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) {
        // One lock for the whole setup: a task that finishes at once waits
        // here briefly instead of racing a half-built state.
        state.withLock { s in
            guard !s.done else { continuation.resume(throwing: CancellationError()); return }
            s.continuation = continuation
            s.tasks = [
                Task {
                    do { self.finish(.success(try await operation())) } catch { self.finish(.failure(error)) }
                },
                Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    self.finish(.failure(PeriscopeError.timeout(seconds: seconds)))
                },
            ]
        }
    }

    func finish(_ result: Result<T, Error>) {
        let taken = state.withLock { s -> (CheckedContinuation<T, Error>?, [Task<Void, Never>])? in
            if s.done { return nil }
            s.done = true
            defer { s.continuation = nil; s.tasks = [] }
            return (s.continuation, s.tasks)
        }
        guard let (continuation, tasks) = taken else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}

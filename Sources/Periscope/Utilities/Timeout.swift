import Foundation

func withTimeout<T: Sendable>(
    seconds: Int,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw PeriscopeError.timeout(seconds: seconds)
        }
        guard let result = try await group.next() else {
            throw PeriscopeError.timeout(seconds: seconds)
        }
        group.cancelAll()
        return result
    }
}

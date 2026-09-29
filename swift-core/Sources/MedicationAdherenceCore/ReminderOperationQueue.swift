import Foundation

/// Serializes complete system-reminder operations, including their suspension points.
/// Enqueue immediately after persistence succeeds, before creating other asynchronous work.
public final class ReminderOperationQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var tail: Task<Void, Never>?

    public init() {}

    /// Cancelling the returned waiter does not discard a committed reminder operation.
    /// Operations must not enqueue and await another operation on this same queue.
    @discardableResult
    public func enqueue<Result: Sendable>(
        _ operation: @escaping @Sendable () async -> Result
    ) -> Task<Result, Never> {
        lock.lock()
        defer { lock.unlock() }
        let predecessor = tail
        let task = Task {
            await predecessor?.value
            return await operation()
        }
        tail = Task { _ = await task.value }
        return Task { await task.value }
    }
}

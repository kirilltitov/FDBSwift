import Foundation
import CFDB
import NIO

public extension FDB {
    /// Begins a new FDB transaction without an event loop
    public func begin() throws -> FDB.Transaction {
        self.debug("Trying to start transaction without eventloop")

        return try FDB.Transaction.begin(try self.getDB())
    }

    /// Begins a new FDB transaction with given event loop
    ///
    /// - parameters:
    ///   - eventLoop: Swift-NIO EventLoop to run future computations
    /// - returns: `EventLoopFuture` with a transaction instance as future value.
    public func begin(on eventLoop: EventLoop) -> EventLoopFuture<FDB.Transaction> {
        do {
            self.debug("Trying to start transaction with eventloop \(Swift.type(of: eventLoop))")

            return eventLoop.newSucceededFuture(
                result: try FDB.Transaction.begin(
                    try self.getDB(),
                    eventLoop
                )
            )
        } catch {
            self.debug("Failed to start transaction with eventloop \(Swift.type(of: eventLoop)): \(error)")
            return FDB.dummyEventLoop.newFailedFuture(error: error)
        }
    }

    /// Executes given transactional closure with appropriate retry logic
    ///
    /// Retry logic kicks in if `notCommitted` (1020) error was thrown during commit event. You must commit
    /// the transaction yourself. Additionally, this transactional closure should be idempotent in order to exclude
    /// unexpected behaviour.
    public func withTransaction<T>(
        on eventLoop: EventLoop,
        _ block: @escaping (FDB.Transaction) throws -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        func transactionRoutine(_ transaction: FDB.Transaction) -> EventLoopFuture<T> {
            let result: EventLoopFuture<T>

            do {
                result = try block(transaction).checkingRetryableError(for: transaction)
            } catch {
                result = eventLoop.newFailedFuture(error: error)
            }

            return result.thenIfError { (error: Swift.Error) -> EventLoopFuture<T> in
                if case let FDB.Error.transactionRetry(transaction) = error {
                    transaction.incrementRetries()
                    return transactionRoutine(transaction)
                }
                return eventLoop.newFailedFuture(error: error)
            }
        }

        return self
            .begin(on: eventLoop)
            .then(transactionRoutine)
    }

    /// Executes given transactional closure with appropriate retry logic
    ///
    /// This function will block current thread during execution
    ///
    /// Retry logic kicks in if `notCommitted` (1020) error was thrown during commit event. You must commit
    /// the transaction yourself. Additionally, this transactional closure should be idempotent in order to exclude
    /// unexpected behaviour.
    public func withTransaction<T>(
        _ block: @escaping (FDB.Transaction) throws -> T
    ) throws -> T {
        func transactionRoutine(_ transaction: FDB.Transaction) throws -> T {
            do {
                return try block(transaction)
            } catch let FDB.Error.transactionRetry(transaction) {
                return try transactionRoutine(transaction)
            }
        }

        return try transactionRoutine(self.begin())
    }
}

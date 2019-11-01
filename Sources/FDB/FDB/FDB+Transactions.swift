import Foundation
import CFDB
import NIO

public extension FDB {
    /// Begins a new FDB transaction without an event loop
    func begin() throws -> AnyFDBTransaction {
        FDB.logger.debug("Trying to start transaction without eventloop")

        return try FDB.Transaction.begin(try self.getDB())
    }

    /// Begins a new FDB transaction with given event loop
    ///
    /// - parameters:
    ///   - eventLoop: Swift-NIO EventLoop to run future computations
    /// - returns: `EventLoopFuture` with a transaction instance as future value.
    func begin(on eventLoop: EventLoop) -> EventLoopFuture<AnyFDBTransaction> {
        do {
            FDB.logger.debug("Trying to start transaction with eventloop \(Swift.type(of: eventLoop))")

            return eventLoop.makeSucceededFuture(
                try FDB.Transaction.begin(
                    try self.getDB(),
                    eventLoop
                )
            )
        } catch {
            FDB.logger.error("Failed to start transaction with eventloop \(Swift.type(of: eventLoop)): \(error)")
            return FDB.dummyEventLoop.makeFailedFuture(error)
        }
    }

    /// Executes given transactional closure with appropriate retry logic
    ///
    /// Retry logic kicks in if `notCommitted` (1020) error was thrown during commit event. You must commit
    /// the transaction yourself. Additionally, this transactional closure should be idempotent in order to exclude
    /// unexpected behaviour.
    func withTransaction<T>(
        on eventLoop: EventLoop,
        _ block: @escaping (AnyFDBTransaction) throws -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        func transactionRoutine(_ transaction: AnyFDBTransaction) -> EventLoopFuture<T> {
            let result: EventLoopFuture<T>

            do {
                result = try block(transaction).checkingRetryableError(for: transaction)
            } catch {
                result = eventLoop.makeFailedFuture(error)
            }

            return result.flatMapError { (error: Swift.Error) -> EventLoopFuture<T> in
                if case let FDB.Error.transactionRetry(transaction) = error {
                    (transaction as? FDB.Transaction)?.incrementRetries()
                    return transactionRoutine(transaction)
                }
                return eventLoop.makeFailedFuture(error)
            }
        }

        return self
            .begin(on: eventLoop)
            .flatMap(transactionRoutine)
    }

    /// Executes given transactional closure with appropriate retry logic
    ///
    /// This function will block current thread during execution
    ///
    /// Retry logic kicks in if `notCommitted` (1020) error was thrown during commit event. You must commit
    /// the transaction yourself. Additionally, this transactional closure should be idempotent in order to exclude
    /// unexpected behaviour.
    func withTransaction<T>(_ block: @escaping (AnyFDBTransaction) throws -> T) throws -> T {
        func transactionRoutine(_ transaction: AnyFDBTransaction) throws -> T {
            do {
                return try block(transaction)
            } catch let FDB.Error.transactionRetry(transaction) {
                (transaction as? FDB.Transaction)?.incrementRetries()
                return try transactionRoutine(transaction)
            }
        }

        return try transactionRoutine(self.begin())
    }
}

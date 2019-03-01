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
    
    public func withTransaction<T>(
        on eventLoop: EventLoop,
        commit: Bool = false,
        _ closure: @escaping (FDB.Transaction) throws -> EventLoopFuture<T>
    ) -> EventLoopFuture<T> {
        func transactionRoutine(_ transaction: FDB.Transaction) -> EventLoopFuture<(T, FDB.Transaction)> {
            let result: EventLoopFuture<(T, FDB.Transaction)>
            do {
                result = try closure(transaction).map { _result in (_result, transaction) }
            } catch {
                result = eventLoop.newFailedFuture(error: error)
            }
            return result
        }

        return self
            .begin(on: eventLoop)
            .then(transactionRoutine)
            .then { (result: T, transaction: FDB.Transaction) in
                let resultFuture: EventLoopFuture<(T, FDB.Transaction)>
                if commit {
                    resultFuture = transaction
                        .commit()
                        .map { _ in (result, transaction) }
                } else {
                    resultFuture = eventLoop.newSucceededFuture(result: (result, transaction))
                }
                return resultFuture
            }
            .thenIfError { (error: Swift.Error) -> EventLoopFuture<(T, FDB.Transaction)> in
                if case let FDB.Error.transactionRetry(transaction) = error {
                    self.debug("Retrying transaction")
                    return transactionRoutine(transaction)
                }
                return eventLoop.newFailedFuture(error: error)
            }
            .map { result, transaction in result }
    }
}

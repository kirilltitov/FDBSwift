import Foundation
import CFDB
import NIO

public extension FDB {
    func begin() throws -> AnyFDBTransaction {
        FDB.logger.debug("Trying to start transaction without eventloop")

        return try FDB.Transaction.begin(try self.getDB())
    }

    func begin(on eventLoop: EventLoop) -> EventLoopFuture<AnyFDBTransaction> {
        FDB.logger.debug("Trying to start transaction with eventloop \(Swift.type(of: eventLoop))")

        let promise: EventLoopPromise<AnyFDBTransaction> = eventLoop.makePromise()

        do {
            promise.succeed(
                try FDB.Transaction.begin(
                    try self.getDB(),
                    eventLoop
                )
            )
        } catch {
            FDB.logger.error("Failed to start transaction with eventloop \(Swift.type(of: eventLoop)): \(error)")
            promise.fail(error)
        }

        return promise.futureResult
    }

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

    func withTransaction<T>(_ block: @escaping (AnyFDBTransaction) async throws -> T) async throws -> T {
        func transactionRoutine(_ transaction: AnyFDBTransaction) async throws -> T {
            do {
                return await try block(transaction)
            } catch let FDB.Error.transactionRetry(transaction) {
                (transaction as? FDB.Transaction)?.incrementRetries()
                return await try transactionRoutine(transaction)
            }
        }

        return await try transactionRoutine(self.begin())
    }
}

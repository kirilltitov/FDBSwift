import Foundation
import CFDB

public extension FDB {
    /// Default maximum number of retries for `withTransaction`
    static let defaultTransactionRetryLimit = 100

    func begin() throws -> AnyFDBTransaction {
        try FDB.Transaction.begin(try self.getDB())
    }

    func withTransaction<T>(_ block: @escaping (AnyFDBTransaction) async throws -> T) async throws -> T {
        try await self.withTransaction(retryLimit: FDB.defaultTransactionRetryLimit, block)
    }

    /// Executes given block within a transaction, replaying it on retryable errors.
    ///
    /// - parameters:
    ///   - retryLimit: Maximum number of retries, after which `FDB.Error.transactionRetryLimitExceeded` is thrown.
    ///                 Negative value means no limit (not recommended).
    ///   - block: Transaction body. It may be executed several times, so it must be idempotent.
    func withTransaction<T>(
        retryLimit: Int,
        _ block: @escaping (AnyFDBTransaction) async throws -> T
    ) async throws -> T {
        let transaction = try self.begin()
        var retries = 0

        while true {
            do {
                return try await block(transaction)
            } catch FDB.Error.transactionRetry {
                if retryLimit >= 0 && retries >= retryLimit {
                    throw FDB.Error.transactionRetryLimitExceeded
                }
                retries += 1
                (transaction as? FDB.Transaction)?.incrementRetries()
            }
        }
    }
}

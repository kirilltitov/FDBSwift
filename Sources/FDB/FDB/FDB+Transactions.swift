import Foundation
import CFDB

public extension FDB {
    func begin() throws -> AnyFDBTransaction {
        try FDB.Transaction.begin(try self.getDB())
    }

    func withTransaction<T>(_ block: @escaping (AnyFDBTransaction) async throws -> T) async throws -> T {
        func transactionRoutine(_ transaction: AnyFDBTransaction) async throws -> T {
            do {
                return try await block(transaction)
            } catch FDB.Error.transactionRetry {
                (transaction as? FDB.Transaction)?.incrementRetries()
                return try await transactionRoutine(transaction)
            }
        }

        return try await transactionRoutine(self.begin())
    }
}

import Foundation
import CFDB

public extension FDB.Connector {
    func begin() throws -> any FDBTransaction {
        try FDB.Transaction.begin(try self.getDB())
    }

    func withTransaction<T>(_ block: @escaping (any FDBTransaction) async throws -> T) async throws -> T {
        func transactionRoutine(_ transaction: any FDBTransaction) async throws -> T {
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

import Foundation
import CFDB

public extension FDBConnector {
    func withTransaction<T>(_ block: @escaping (any FDBTransaction) async throws -> T) async throws -> T {
        let transaction = try self.begin()

        while true {
            do {
                return try await block(transaction)
            } catch FDB.Error.transactionRetry {
                (transaction as? FDB.Transaction)?.incrementRetries()
                continue
            }
        }
    }
}

public extension FDB.Connector {
    func begin() throws -> any FDBTransaction {
        try FDB.Transaction.begin(try self.getDB())
    }
}

import Foundation
import CFDB

public extension FDB {
    func begin() throws -> AnyFDBTransaction {
        FDB.logger.debug("Trying to start transaction without eventloop")

        return try FDB.Transaction.begin(try self.getDB())
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

import CFDB

public class Transaction {
    public var pointer: OpaquePointer!

    public init(_ pointer: OpaquePointer? = nil) {
        self.pointer = pointer
    }

    class func begin(_ db: FDB.Database) throws -> Transaction {
        let transaction = Transaction()
        let transactionErrno = fdb_database_create_transaction(db, &transaction.pointer)
        guard transactionErrno == 0 else {
            throw Error.TransactionBeginError(getErrorInfo(for: errno), errno)
        }
        return transaction
    }

    deinit {
        fdb_transaction_destroy(self.pointer)
    }

    public func commit() throws {
        let commitFuture = try fdb_transaction_commit(self.pointer).waitForFuture()
        let commitError = fdb_future_get_error(commitFuture.pointer)
        guard commitError == 0 else {
            let retryFuture = try fdb_transaction_on_error(self.pointer, commitError).waitForFuture()
            let retryError = fdb_future_get_error(retryFuture.pointer)
            guard retryError == 0 else {
                throw Error.TransactionCommitError(getErrorInfo(for: retryError), retryError)
            }
            throw Error.TransactionRetry("Retry this transaction")
        }
    }

    public func set(key: Bytes, value: Bytes, commit: Bool = true) throws {
        fdb_transaction_set(self.pointer, key, Int32(key.count), value, Int32(value.count))
        if commit {
            try self.commit()
        }
    }

    public func get(key: Bytes, snapshot: Int32 = 0, commit: Bool = true) throws -> Bytes? {
        let future = try fdb_transaction_get(self.pointer, key, Int32(key.count), snapshot).waitForFuture()
        var readValueFound: Int32 = 0
        var readValue: UnsafePointer<Byte>!
        var readValueLength: Int32 = 0
        let getErrno = fdb_future_get_value(future.pointer, &readValueFound, &readValue, &readValueLength)
        guard getErrno == 0 else {
            throw Error.TransactionGetError(getErrorInfo(for: getErrno), getErrno)
        }
        if commit {
            try self.commit()
        }
        guard readValueFound > 0 else {
            return nil
        }
        return readValue.getBytes(length: readValueLength)
    }

    public func clear(key: Bytes, commit: Bool = true) throws {
        fdb_transaction_clear(self.pointer, key, Int32(key.count))
        if commit {
            try self.commit()
        }
    }
}

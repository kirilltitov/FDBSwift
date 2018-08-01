import CFDB

public class Transaction {
    internal var pointer: OpaquePointer

    public init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        fdb_transaction_destroy(self.pointer)
    }

    public class func begin(_ db: FDB.Database) throws -> Transaction {
        var ptr: OpaquePointer!
        try fdb_database_create_transaction(db, &ptr).orThrow()
        return Transaction(ptr)
    }

    public func cancel() {
        fdb_transaction_cancel(self.pointer)
    }

    public func reset() {
        fdb_transaction_reset(self.pointer)
    }

    public func clear(key: FDBKey) {
        let keyBytes = key.asFDBKey()
        fdb_transaction_clear(self.pointer, keyBytes, keyBytes.length)
    }

    public func clear(begin: FDBKey, end: FDBKey) {
        let beginBytes = begin.asFDBKey()
        let endBytes = end.asFDBKey()
        fdb_transaction_clear_range(self.pointer, beginBytes, beginBytes.length, endBytes, endBytes.length)
    }

    public func clear(range: RangeFDBKey) {
        self.clear(begin: range.begin, end: range.end)
    }

    public func atomic(_ op: FDB.MutationType, key: FDBKey, value: Bytes) {
        let keyBytes = key.asFDBKey()
        fdb_transaction_atomic_op(
            self.pointer,
            keyBytes,
            keyBytes.length,
            value,
            value.length,
            FDBMutationType(op.rawValue)
        )
    }
}

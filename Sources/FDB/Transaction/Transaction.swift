import CFDB
import NIO

public class Transaction {
    internal let pointer: OpaquePointer
    internal let eventLoop: EventLoop?

    public required init(_ pointer: OpaquePointer, _ eventLoop: EventLoop? = nil) {
        self.pointer = pointer
        self.eventLoop = eventLoop
    }

    deinit {
        fdb_transaction_destroy(self.pointer)
    }

    public class func begin(_ db: FDB.Database, _ eventLoop: EventLoop? = nil) throws -> Transaction {
        var ptr: OpaquePointer!
        try fdb_database_create_transaction(db, &ptr).orThrow()
        return Transaction(ptr, eventLoop)
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

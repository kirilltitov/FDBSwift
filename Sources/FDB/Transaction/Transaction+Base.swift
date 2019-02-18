import CFDB
import NIO

public extension FDB {
    public class Transaction {
        internal let DBPointer: OpaquePointer
        internal let eventLoop: EventLoop?
        
        internal init(_ DBPointer: OpaquePointer, _ eventLoop: EventLoop? = nil) {
            self.DBPointer = DBPointer
            self.eventLoop = eventLoop
        }
        
        deinit {
            fdb_transaction_destroy(self.DBPointer)
        }
        
        public class func begin(_ db: FDB.Database, _ eventLoop: EventLoop? = nil) throws -> FDB.Transaction {
            var ptr: OpaquePointer!
            try fdb_database_create_transaction(db, &ptr).orThrow()
            return FDB.Transaction(ptr, eventLoop)
        }
        
        public func cancel() {
            fdb_transaction_cancel(self.DBPointer)
        }
        
        public func reset() {
            fdb_transaction_reset(self.DBPointer)
        }
        
        public func clear(key: FDBKey) {
            let keyBytes = key.asFDBKey()
            fdb_transaction_clear(self.DBPointer, keyBytes, keyBytes.length)
        }
        
        public func clear(begin: FDBKey, end: FDBKey) {
            let beginBytes = begin.asFDBKey()
            let endBytes = end.asFDBKey()
            fdb_transaction_clear_range(self.DBPointer, beginBytes, beginBytes.length, endBytes, endBytes.length)
        }
        
        public func clear(range: FDB.RangeKey) {
            self.clear(begin: range.begin, end: range.end)
        }
        
        public func atomic(_ op: FDB.MutationType, key: FDBKey, value: Bytes) {
            let keyBytes = key.asFDBKey()
            fdb_transaction_atomic_op(
                self.DBPointer,
                keyBytes,
                keyBytes.length,
                value,
                value.length,
                FDBMutationType(op.rawValue)
            )
        }
    }
}


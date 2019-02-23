import CFDB
import NIO

public extension FDB {
    public class Transaction {
        internal let pointer: OpaquePointer
        internal let eventLoop: EventLoop?
        
        internal init(_ DBPointer: OpaquePointer, _ eventLoop: EventLoop? = nil) {
            self.pointer = DBPointer
            self.eventLoop = eventLoop

            let debugInfoSuffix: String
            if let el = eventLoop {
                debugInfoSuffix = "on \(Swift.type(of: el))"
            } else {
                debugInfoSuffix = "without event loop"
            }

            self.debug("Started transaction \(debugInfoSuffix)")
        }
        
        deinit {
            fdb_transaction_destroy(self.pointer)
        }

        internal func debug(_ message: String) {
            FDB.debug("[Transaction] [\(ObjectIdentifier(self).hashValue)] \(message)")
        }
        
        internal class func begin(_ db: FDB.Database, _ eventLoop: EventLoop? = nil) throws -> FDB.Transaction {
            var ptr: OpaquePointer!

            try fdb_database_create_transaction(db, &ptr).orThrow()

            return FDB.Transaction(ptr, eventLoop)
        }
        
        public func cancel() {
            fdb_transaction_cancel(self.pointer)
        }
        
        public func reset() {
            fdb_transaction_reset(self.pointer)
        }
        
        public func clear(key: AnyFDBKey) {
            let keyBytes = key.asFDBKey()
            fdb_transaction_clear(self.pointer, keyBytes, keyBytes.length)
        }
        
        public func clear(begin: AnyFDBKey, end: AnyFDBKey) {
            let beginBytes = begin.asFDBKey()
            let endBytes = end.asFDBKey()
            fdb_transaction_clear_range(self.pointer, beginBytes, beginBytes.length, endBytes, endBytes.length)
        }
        
        public func clear(range: FDB.RangeKey) {
            self.clear(begin: range.begin, end: range.end)
        }
        
        public func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) {
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
}


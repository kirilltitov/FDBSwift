import CFDB
import NIO

public extension FDB {
    class Transaction {
        internal typealias Pointer = OpaquePointer

        internal let pointer: Pointer
        internal let eventLoop: EventLoop?
        internal private(set) var retries: Int = 0

        /// Creates a new instance of a previously started FDB transaction
        internal init(_ pointer: Pointer, _ eventLoop: EventLoop? = nil) {
            self.pointer = pointer
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
            self.destroy()
        }

        /// Destroys current transaction. It becomes unusable after this.
        func destroy() {
            fdb_transaction_destroy(self.pointer)
        }

        internal func incrementRetries() {
            self.retries += 1
            self.debug("Retry #\(self.retries)")
        }

        /// Prints verbose debug message to stdout (if `FDB.verbose` is `true`)
        internal func debug(_ message: String) {
            FDB.debug("[Transaction] [\(ObjectIdentifier(self).hashValue)] \(message)")
        }

        /// Begins a new FDB transactionon on given FDB database pointer and optional event loop
        internal class func begin(_ db: FDB.Database, _ eventLoop: EventLoop? = nil) throws -> FDB.Transaction {
            var pointer: Pointer!

            try fdb_database_create_transaction(db, &pointer).orThrow()

            return FDB.Transaction(pointer, eventLoop)
        }

        /// Cancels the transaction. All pending or future uses of the transaction will return
        /// a `transaction_cancelled` error. The transaction can be used again after it is `reset`.
        func cancel() {
            self.debug("Cancelling transaction")
            fdb_transaction_cancel(self.pointer)
        }

        /// Reset transaction to its initial state.
        /// This is similar to creating a new transaction after destroying previous one.
        func reset() {
            self.debug("Resetting transaction")
            fdb_transaction_reset(self.pointer)
        }

        /// Clears given key in FDB cluster
        ///
        /// - parameters:
        ///   - key: FDB key
        func clear(key: AnyFDBKey) {
            let keyBytes = key.asFDBKey()
            fdb_transaction_clear(self.pointer, keyBytes, keyBytes.length)
        }

        /// Clears keys in given range in FDB cluster
        ///
        /// - parameters:
        ///   - begin: Begin key
        ///   - end: End key
        func clear(begin: AnyFDBKey, end: AnyFDBKey) {
            let beginBytes = begin.asFDBKey()
            let endBytes = end.asFDBKey()
            fdb_transaction_clear_range(self.pointer, beginBytes, beginBytes.length, endBytes, endBytes.length)
        }

        /// Clears keys in given range in FDB cluster
        ///
        /// - parameters:
        ///   - range: Range key
        func clear(range: FDB.RangeKey) {
            self.clear(begin: range.begin, end: range.end)
        }

        /// Peforms an atomic operation in FDB cluster on given key with given value bytes
        ///
        ///
        /// - parameters:
        ///   - _: Atomic operation
        ///   - key: FDB key
        ///   - value: Value bytes
        func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) {
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

        /// Sets the snapshot read version used by a transaction
        ///
        /// This is not needed in simple cases. If the given version is too old, subsequent reads will fail
        /// with error_code_past_version; if it is too new, subsequent reads may be delayed indefinitely and/or fail
        /// with error_code_future_version. If any of fdb_transaction_get_*() have been called
        /// on this transaction already, the result is undefined.
        func setReadVersion(version: Int64) {
            fdb_transaction_set_read_version(self.pointer, version)
        }
    }
}

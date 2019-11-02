import CFDB
import NIO
import Logging

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

            self.log("Started transaction \(debugInfoSuffix)")
        }

        deinit {
            self.destroy()
        }

        /// Destroys current transaction. It becomes unusable after this.
        public func destroy() {
            fdb_transaction_destroy(self.pointer)
        }

        internal func incrementRetries() {
            self.retries += 1
            self.log("Retry #\(self.retries)", level: .info)
        }

        /// Logs message to Logger (if `FDB.verbose` is `true`)
        @inlinable internal func log(_ message: String, level: Logger.Level = .debug) {
            var logger = FDB.logger
            logger[metadataKey: "trid"] = "\(ObjectIdentifier(self).hashValue)"

            logger.log(
                level: level,
                "[FDB.Transaction] \(message)"
            )
        }

        /// Begins a new FDB transactionon on given FDB database pointer and optional event loop
        internal class func begin(_ db: FDB.Database, _ eventLoop: EventLoop? = nil) throws -> FDB.Transaction {
            var pointer: Pointer!

            try fdb_database_create_transaction(db, &pointer).orThrow()

            return FDB.Transaction(pointer, eventLoop)
        }

        /// Cancels the transaction. All pending or future uses of the transaction will return
        /// a `transaction_cancelled` error. The transaction can be used again after it is `reset`.
        public func cancel() {
            self.log("Cancelling transaction")
            fdb_transaction_cancel(self.pointer)
        }

        /// Reset transaction to its initial state.
        /// This is similar to creating a new transaction after destroying previous one.
        public func reset() {
            self.log("Resetting transaction")
            fdb_transaction_reset(self.pointer)
        }

        /// Clears given key in FDB cluster
        ///
        /// - parameters:
        ///   - key: FDB key
        public func clear(key: AnyFDBKey) {
            let keyBytes = key.asFDBKey()
            fdb_transaction_clear(self.pointer, keyBytes, keyBytes.length)
        }

        /// Clears keys in given range in FDB cluster
        ///
        /// - parameters:
        ///   - begin: Begin key
        ///   - end: End key
        public func clear(begin: AnyFDBKey, end: AnyFDBKey) {
            let beginBytes = begin.asFDBKey()
            let endBytes = end.asFDBKey()
            fdb_transaction_clear_range(self.pointer, beginBytes, beginBytes.length, endBytes, endBytes.length)
        }

        /// Clears keys in given range in FDB cluster
        ///
        /// - parameters:
        ///   - range: Range key
        public func clear(range: FDB.RangeKey) {
            self.clear(begin: range.begin, end: range.end)
        }

        /// Peforms an atomic operation in FDB cluster on given key with given value bytes
        ///
        ///
        /// - parameters:
        ///   - _: Atomic operation
        ///   - key: FDB key
        ///   - value: Value bytes
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

        /// Sets the snapshot read version used by a transaction
        ///
        /// This is not needed in simple cases. If the given version is too old, subsequent reads will fail
        /// with error_code_past_version; if it is too new, subsequent reads may be delayed indefinitely and/or fail
        /// with error_code_future_version. If any of fdb_transaction_get_*() have been called
        /// on this transaction already, the result is undefined.
        public func setReadVersion(version: Int64) {
            fdb_transaction_set_read_version(self.pointer, version)
        }
    }
}

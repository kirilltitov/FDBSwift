import CFDB
import NIO
import Logging

public extension FDB {
    class Transaction: AnyFDBTransaction {
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

        public func destroy() {
            self.log("Destroying transaction")

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
        internal class func begin(_ db: FDB.Database, _ eventLoop: EventLoop? = nil) throws -> AnyFDBTransaction {
            var pointer: Pointer!

            try fdb_database_create_transaction(db, &pointer).orThrow()

            return FDB.Transaction(pointer, eventLoop)
        }

        public func cancel() {
            self.log("Cancelling transaction")

            fdb_transaction_cancel(self.pointer)
        }

        public func reset() {
            self.log("Resetting transaction")

            fdb_transaction_reset(self.pointer)
        }

        public func clear(key: AnyFDBKey) {
            let keyBytes = key.asFDBKey()

            self.log("Clearing key '\(keyBytes.string.safe)'")

            fdb_transaction_clear(self.pointer, keyBytes, keyBytes.length)
        }

        public func clear(begin: AnyFDBKey, end: AnyFDBKey) {
            let beginBytes = begin.asFDBKey()
            let endBytes = end.asFDBKey()

            self.log("Clearing range from key '\(beginBytes.string.safe)' to '\(endBytes.string.safe)'")

            fdb_transaction_clear_range(self.pointer, beginBytes, beginBytes.length, endBytes, endBytes.length)
        }

        public func clear(range: FDB.RangeKey) {
            self.clear(begin: range.begin, end: range.end)
        }

        public func atomic(_ op: FDB.MutationType, key: AnyFDBKey, value: Bytes) {
            let keyBytes = key.asFDBKey()

            self.log("[Atomic] [\(op)] Setting '\(value.string.safe)' to key '\(keyBytes.string.safe)'")

            fdb_transaction_atomic_op(
                self.pointer,
                keyBytes,
                keyBytes.length,
                value,
                value.length,
                FDBMutationType(op.rawValue)
            )
        }

        public func setReadVersion(version: Int64) {
            self.log("Setting read version to '\(version)'")

            fdb_transaction_set_read_version(self.pointer, version)
        }
    }
}

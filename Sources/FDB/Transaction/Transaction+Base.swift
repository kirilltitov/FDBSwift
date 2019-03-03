import CFDB
import NIO

internal extension EventLoopFuture {
    func checkingRetryableError(for transaction: FDB.Transaction) -> EventLoopFuture {
        return self.thenIfError { error in
            guard let FDBError = error as? FDB.Error else {
                return self.eventLoop.newFailedFuture(error: error)
            }

            let onErrorFuture: FDB.Future = fdb_transaction_on_error(transaction.pointer, FDBError.errno).asFuture()

            let promise: EventLoopPromise<T> = self.eventLoop.newPromise()

            onErrorFuture.whenVoidReady {
                promise.fail(error: FDB.Error.transactionRetry(transaction: transaction))
            }
            onErrorFuture.whenError(promise.fail)

            return promise.futureResult
        }
    }
}

public extension FDB {
    public class Transaction {
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
        public func destroy() {
            fdb_transaction_destroy(self.pointer)
        }

        internal func incrementRetries() {
            self.retries += 1
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
        public func cancel() {
            fdb_transaction_cancel(self.pointer)
        }

        /// Reset transaction to its initial state.
        /// This is similar to creating a new transaction after destroying previous one.
        public func reset() {
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
    }
}

import CFDB

internal extension FDB {
    /// An internal class representing FDB future value.
    ///
    /// Currently supports only four value types: `Bytes`, `FDB.KeyValuesResult` and `Void`.
    internal class Future<R> {
        internal let pointer: OpaquePointer

        private var failClosure: ((Swift.Error) -> Void)?
        private let isTransaction: Bool

        internal init(_ pointer: OpaquePointer, _ isTransaction: Bool) {
            self.pointer = pointer
            self.isTransaction = isTransaction
        }

        deinit {
            fdb_future_release_memory(self.pointer)
            self.destroy()
        }
        
        /// Destroys current Future. It becomes unusable after this.
        internal func destroy() {
            fdb_future_destroy(self.pointer)
        }

        /// Blocks current thread until future is resolved
        @discardableResult internal func wait() throws -> Future {
            try fdb_future_block_until_ready(self.pointer).orThrow()
            return self
        }

        /// Throws an Error if current future is in error state
        internal func checkError() throws -> Future {
            try fdb_future_get_error(self.pointer).orThrow()
            return self
        }

        /// Blocks current thread until current future is resolved and checks if it's in error state
        @discardableResult internal func waitAndCheck() throws -> Future {
            return try self.wait().checkError()
        }

        /// Performs routine assocated with error state
        internal func fail(with error: Swift.Error, _ file: StaticString = #file, _ line: Int = #line) {
            debugOnly {
                guard let _ = self.failClosure else {
                    print("FDB: no fail closure, caught error \(error) at \(file):\(line)")
                    return
                }
            }
            self.failClosure?(error)
        }

        /// Sets a closure to be executed when (if) current future is in failed state
        internal func whenError(_ closure: @escaping (Swift.Error) -> Void) {
            self.failClosure = closure
        }
        
        //        return promise.futureResult.then { future in
        //            let commitError: fdb_error_t = fdb_future_get_error(future.pointer)
        //            if commitError == 0 {
        //                return eventLoop.newSucceededFuture(result: ())
        //            }
        //            self.debug("Retrying transaction (commit errno \(commitError): \(FDB.Error.getErrorInfo(for: commitError)))")
        //            let retryPromise: EventLoopPromise<Void> = eventLoop.newPromise()
        //            let retryFuture: FDB.Future<Void> = fdb_transaction_on_error(self.pointer, commitError).asFuture()
        //            do {
        //                try retryFuture.whenReady { _retryFuture in
        //                    try fdb_future_get_error(_retryFuture.pointer).orThrow()
        //                    throw FDB.Error.transactionRetry(transaction: self)
        //                }
        //                retryFuture.whenError(retryPromise.fail)
        //            } catch {
        //                self.debug("Bad error during future retry: \(error)")
        //                retryPromise.fail(error: error)
        //            }
        //            return retryPromise.futureResult
        //        }
        
        internal func wrappingRecoverableError(_ closure: @escaping () throws -> Void) rethrows {
            let error = fdb_future_get_error(self.pointer)
            if error == 0 {
                try closure()
                return
            }
            let onErrorFuture = fdb_transaction_on_error(self.pointer, error)
        }
    }
}

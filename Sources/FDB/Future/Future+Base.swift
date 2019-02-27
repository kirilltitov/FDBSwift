import CFDB

internal extension FDB {
    /// An internal class representing FDB future value.
    ///
    /// Currently supports only four value types: `Bytes`, `FDB.KeyValuesResult` and `Void`.
    internal class Future<R> {
        internal let pointer: OpaquePointer

        private var failClosure: ((Swift.Error) -> Void)?

        internal init(_ pointer: OpaquePointer) {
            self.pointer = pointer
        }

        deinit {
            fdb_future_release_memory(self.pointer)
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
    }
}

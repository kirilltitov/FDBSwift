import CFDB

internal extension FDB {
    /// An internal class representing FDB future value.
    ///
    /// Currently supports only four value types: `Bytes`, `FDB.KeyValuesResult` and `Void`.
    class Future {
        typealias Callback = (Future) -> Void

        class Box {
            let future: Future
            let callback: (Future) -> Void

            init(_ future: Future, _ callback: @escaping Callback) {
                self.future = future
                self.callback = callback
            }
        }

        let pointer: OpaquePointer
        let ref: Any?

        private var failClosure: ((Swift.Error) -> Void)?

        init(_ pointer: OpaquePointer, _ ref: Any? = nil) {
            self.pointer = pointer
            self.ref = ref
        }

        deinit {
            fdb_future_release_memory(self.pointer)
            self.destroy()
        }

        /// Destroys current Future. It becomes unusable after this.
        func destroy() {
            fdb_future_destroy(self.pointer)
        }

        /// Blocks current thread until future is resolved
        @discardableResult
        func wait() throws -> Future {
            try fdb_future_block_until_ready(self.pointer).orThrow()
            return self
        }

        /// Throws an Error if current future is in error state
        func checkError() throws -> Future {
            try fdb_future_get_error(self.pointer).orThrow()
            return self
        }

        /// Blocks current thread until current future is resolved and checks if it's in error state
        @discardableResult
        func waitAndCheck() throws -> Future {
            return try self.wait().checkError()
        }

        /// Performs routine assocated with error state
        func fail(with error: Swift.Error, _ file: StaticString = #file, _ line: Int = #line) {
            debugOnly {
                guard let _ = self.failClosure else {
                    FDB.logger.error("No fail closure, caught error \(error) at \(file):\(line)")
                    return
                }
            }

            self.failClosure?(error)
        }

        /// Sets a closure to be executed when (if) current future is in failed state
        func whenError(_ closure: @escaping (Swift.Error) -> Void) {
            self.failClosure = closure
        }

        /// Sets a closure to be executed when current future is resolved
        func whenReady(_ callback: @escaping Callback) {
            do {
                try fdb_future_set_callback(
                    self.pointer,
                    { futurePtr, boxPtr in
                        let unwrappedBox = Unmanaged<Box>.fromOpaque(boxPtr!).takeRetainedValue()
                        let errno = fdb_future_get_error(futurePtr)
                        if errno != 0 {
                            let error = FDB.Error.from(errno: errno)
                            FDB.logger.debug("Failing future with error '\(error)' (\(errno)): '\(error.getDescription())'")
                            unwrappedBox.future.fail(with: error)
                        } else {
                            unwrappedBox.callback(unwrappedBox.future)
                        }
                    },
                    Unmanaged.passRetained(Box(self, callback)).toOpaque()
                ).orThrow()
            } catch {
                self.fail(with: error)
            }
        }
    }
}

import CFDB
import LGNLog

internal extension FDB {
    /// An internal class representing FDB future value.
    ///
    /// Currently supports only four value types: `Bytes`, `FDB.KeyValuesResult` and `Void`.
    class Future {
        enum State {
            case Awaiting
            case Resolved
            case Error(FDB.Errno)
        }

        class Box {
            let future: Future
            let continuation: UnsafeContinuation<Void, Swift.Error>

            init(_ future: Future, _ continuation: UnsafeContinuation<Void, Swift.Error>) {
                self.future = future
                self.continuation = continuation
            }
        }

        let pointer: OpaquePointer
        let ref: Any?
        var state: State = .Awaiting

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

        func resolved() async throws {
            try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, Swift.Error>) -> Void in
                do {
                    try fdb_future_set_callback(
                        self.pointer,
                        { futurePtr, boxPtr in
                            let box = Unmanaged<Box>.fromOpaque(boxPtr!).takeRetainedValue()
                            let errno = fdb_future_get_error(futurePtr)
                            if errno != 0 {
                                Logger.current.debug("Failing future with errno \(errno)")
                                box.future.state = .Error(errno)
                            } else {
                                box.future.state = .Resolved
                            }
                            box.continuation.resume()
                        },
                        Unmanaged.passRetained(Box(self, continuation)).toOpaque()
                    ).orThrow()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

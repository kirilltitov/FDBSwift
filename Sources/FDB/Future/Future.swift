import CFDB

public class Future<R> {
    public let pointer: OpaquePointer

    private var failClosure: ((Error) -> Void)? = nil

    public init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        fdb_future_release_memory(self.pointer)
        fdb_future_destroy(self.pointer)
    }

    @discardableResult public func wait() throws -> Future {
        try fdb_future_block_until_ready(self.pointer).orThrow()
        return self
    }

    public func checkError() throws -> Future {
        try fdb_future_get_error(self.pointer).orThrow()
        return self
    }

    @discardableResult public func waitAndCheck() throws -> Future {
        return try self.wait().checkError()
    }

    internal func fail(with error: Error) {
        debugOnly {
            guard let _ = self.failClosure else {
                print("FDB: no fail closure, caught error \(error)")
                return
            }
        }
        self.failClosure?(error)
    }

    public func whenError(_ closure: @escaping (Error) -> Void) {
        self.failClosure = closure
    }
}

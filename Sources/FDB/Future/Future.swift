import CFDB

public class Future<R> {
    public let pointer: OpaquePointer

    private var failClosure: ((Error) -> Void)? = nil

    public init(_ pointer: OpaquePointer) {
        self.pointer = pointer
        dump("init   \(ObjectIdentifier(self)):\(self.pointer)")
    }

    deinit {
        dump("deinit \(ObjectIdentifier(self)):\(self.pointer)")
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
        guard let failClosure = self.failClosure else {
            // TODO: this should be debug only
            print("FDB: no fail closure, caught error \(error)")
            return
        }
        failClosure(error)
    }
}

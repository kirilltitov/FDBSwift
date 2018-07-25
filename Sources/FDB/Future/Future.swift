import CFDB

public class Future<R> {
    let pointer: OpaquePointer

    public init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        fdb_future_release_memory(self.pointer)
        fdb_future_destroy(self.pointer)
    }

    public func wait() throws -> Future {
        try fdb_future_block_until_ready(self.pointer).orThrow()
        return self
    }

    public func checkError() throws -> Future {
        try fdb_future_get_error(self.pointer).orThrow()
        return self
    }

    public func waitAndCheck() throws -> Future {
        return try self.wait().checkError()
    }
}

import CFDB

internal class Future {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        fdb_future_release_memory(self.pointer)
        fdb_future_destroy(self.pointer)
    }

    func wait() throws -> Future {
        try fdb_future_block_until_ready(self.pointer).orThrow()
        return self
    }

    func checkError() throws -> Future {
        try fdb_future_get_error(self.pointer).orThrow()
        return self
    }

    func waitAndCheck() throws -> Future {
        return try self.wait().checkError()
    }
}

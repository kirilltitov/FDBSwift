import CFDB

public class Future {
    public enum Error: Swift.Error {
        case WaitError(String, Int32)
        case ResultError(String, Int32)
    }

    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        fdb_future_destroy(self.pointer)
    }

    func wait() throws -> Future {
        let errno = fdb_future_block_until_ready(self.pointer)
        guard errno == 0 else {
            throw Error.WaitError(getErrorInfo(for: errno), errno)
        }
        return self
    }

    func checkError() throws -> Future {
        let errno = fdb_future_get_error(self.pointer)
        guard errno == 0 else {
            throw Error.ResultError(getErrorInfo(for: errno), errno)
        }
        return self
    }

    func waitAndCheck() throws -> Future {
        return try self.wait().checkError()
    }
}

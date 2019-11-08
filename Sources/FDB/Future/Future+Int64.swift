import CFDB

extension FDB.Future {
    /// Sets a closure to be executed when current future is resolved
    func whenInt64Ready(_ callback: @escaping (Int64) -> Void) throws {
        self.whenReady { future in
            do {
                try callback(future.getVersion())
            } catch {
                future.fail(with: error)
            }
        }
    }

    /// Blocks current thread until future is resolved
    internal func wait() throws -> Int64 {
        try self.waitAndCheck()
        return try self.getVersion()
    }

    /// Returns Future's version
    ///
    /// Should be called only when future is resolved
    func getVersion() throws -> Int64 {
        var version: Int64 = 0
        try fdb_future_get_int64(self.pointer, &version).orThrow()
        return version
    }
}

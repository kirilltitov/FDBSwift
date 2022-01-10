import CFDB

extension FDB.Future {
    /// Returns Future's version
    ///
    /// Should be called only when future is resolved
    @inlinable
    internal func getVersion() throws -> Int64 {
        var version: Int64 = 0

        try fdb_future_get_int64(self.pointer, &version).orThrow()

        return version
    }
}

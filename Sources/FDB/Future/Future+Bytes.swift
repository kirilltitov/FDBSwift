import CFDB

extension FDB.Future {
    /// Blocks current thread until future is resolved
    @inlinable
    internal func wait() throws -> Bytes? {
        try self.waitAndCheck().parseBytes()
    }

    /// Parses value bytes result from current future
    ///
    /// Warning: this should be only called if future is in resolved state
    @inlinable
    internal func parseBytes() throws -> Bytes? {
        var readValueFound: Int32 = 0
        var readValue: UnsafePointer<Byte>!
        var readValueLength: Int32 = 0

        try fdb_future_get_value(self.pointer, &readValueFound, &readValue, &readValueLength).orThrow()

        guard readValueFound > 0 else {
            return nil
        }

        return readValue.getBytes(count: readValueLength)
    }
    
    /// Parses key bytes result from current future
    ///
    /// Warning: this should be only called if future is in resolved state
    @inlinable
    internal func parseKeyBytes() throws -> Bytes {
        var readKey: UnsafePointer<Byte>!
        var readKeyLength: Int32 = 0
        try fdb_future_get_key(self.pointer, &readKey, &readKeyLength).orThrow()
        return readKey.getBytes(count: readKeyLength)
    }
}

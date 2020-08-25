import CFDB

extension FDB.Future {
    /// Sets a closure to be executed when current future is resolved, returning bytes for the value
    func whenBytesReady(_ callback: @escaping (Bytes?) -> Void) throws {
        self.whenReady { future in
            do {
                try callback(future.parseBytes())
            } catch {
                future.fail(with: error)
            }
        }
    }
    
    /// Sets a closure to be executed when current future is resolved, returning bytes for the key
    func whenKeyBytesReady(_ callback: @escaping (Bytes) -> Void) throws {
        self.whenReady { future in
            do {
                try callback(future.parseKeyBytes())
            } catch {
                future.fail(with: error)
            }
        }
    }

    /// Blocks current thread until future is resolved
    internal func wait() throws -> Bytes? {
        return try self.waitAndCheck().parseBytes()
    }

    /// Parses value bytes result from current future
    ///
    /// Warning: this should be only called if future is in resolved state
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
    func parseKeyBytes() throws -> Bytes {
        var readKey: UnsafePointer<Byte>!
        var readKeyLength: Int32 = 0
        try fdb_future_get_key(self.pointer, &readKey, &readKeyLength).orThrow()
        return readKey.getBytes(count: readKeyLength)
    }
}

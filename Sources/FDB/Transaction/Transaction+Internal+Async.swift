import CFDB

internal extension FDB.Transaction {
    /// Commits current transaction
    internal func commit() throws -> FDB.Future<Void> {
        return fdb_transaction_commit(self.pointer).asFuture()
    }

    /// Sets bytes to given key in FDB cluster
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - value: bytes value
    internal func set(key: AnyFDBKey, value: Bytes) {
        let keyBytes = key.asFDBKey()
        fdb_transaction_set(self.pointer, keyBytes, keyBytes.length, value, value.length)
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    internal func get(key: AnyFDBKey, snapshot: Bool = false) -> FDB.Future<Bytes?> {
        let keyBytes = key.asFDBKey()
        return fdb_transaction_get(self.pointer, keyBytes, keyBytes.length, snapshot.int).asFuture()
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// - parameters:
    ///   - begin: Begin key
    ///   - end: End key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    internal func get(
        begin: AnyFDBKey,
        end: AnyFDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Bool = false,
        reverse: Bool = false
    ) -> FDB.Future<FDB.KeyValuesResult> {
        let beginBytes = begin.asFDBKey()
        let endBytes = end.asFDBKey()
        return fdb_transaction_get_range(
            self.pointer,
            beginBytes,
            beginBytes.length,
            beginEqual.int,
            beginOffset,
            endBytes,
            endBytes.length,
            endEqual.int,
            endOffset,
            limit,
            targetBytes,
            FDBStreamingMode(mode.rawValue),
            iteration,
            snapshot.int,
            reverse.int
        ).asFuture()
    }

    /// Returns a range of keys and their respective values in given key range
    ///
    /// This function will block current thread during execution
    ///
    /// - parameters:
    ///   - range: Range key
    ///   - beginEqual: Should begin key also include exact key value
    ///   - beginOffset: Begin key offset
    ///   - endEqual: Should end key also include exact key value
    ///   - endOffset: End key offset
    ///   - limit: Limit returned key-value pairs (only relevant when `mode` is `.exact`)
    ///   - targetBytes: If non-zero, indicates a soft cap on the combined number of bytes of keys and values to return
    ///   - mode: The manner in which rows are returned (see `FDB.StreamingMode` docs)
    ///   - iteration: If `mode` is `.iterator`, this arg represent current read iteration (should start from 1)
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    ///   - reverse: If `true`, key-value pairs will be returned in reverse lexicographical order
    internal func get(
        range: FDB.RangeKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .wantAll,
        iteration: Int32 = 1,
        snapshot: Bool = false,
        reverse: Bool = false
    ) -> FDB.Future<FDB.KeyValuesResult> {
        return self.get(
            begin: range.begin,
            end: range.end,
            beginEqual: beginEqual,
            beginOffset: beginOffset,
            endEqual: endEqual,
            endOffset: endOffset,
            limit: limit,
            targetBytes: targetBytes,
            mode: mode,
            iteration: iteration,
            snapshot: snapshot,
            reverse: reverse
        )
    }
}

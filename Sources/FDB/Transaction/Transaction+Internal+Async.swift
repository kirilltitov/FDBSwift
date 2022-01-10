import CFDB

internal extension FDB.Transaction {
    /// Commits current transaction
    func commit() -> FDB.Future {
        self.log("Committing transaction")

        return fdb_transaction_commit(self.pointer).asFuture(ref: self)
    }

    /// Returns bytes value for given key (or `nil` if no key)
    ///
    /// - parameters:
    ///   - key: FDB key
    ///   - snapshot: Snapshot read (i.e. whether this read create a conflict range or not)
    func get(key: AnyFDBKey, snapshot: Bool = false) -> FDB.Future {
        let keyBytes = key.asFDBKey()

        self.log("Getting key '\(keyBytes.string.safe)'")

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
    func get(
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
    ) -> FDB.Future {
        let beginBytes = begin.asFDBKey()
        let endBytes = end.asFDBKey()

        self.log("Getting range from key '\(beginBytes.string.safe)' to '\(endBytes.string.safe)'")

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
    func get(
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
    ) -> FDB.Future {
        self.get(
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

    /// Returns transaction snapshot read version
    func getReadVersion() -> FDB.Future {
        fdb_transaction_get_read_version(self.pointer).asFuture()
    }

    /// Returns versionstamp which was used by any versionstamp operations in this transaction
    func getVersionstamp() -> FDB.Future {
        fdb_transaction_get_versionstamp(self.pointer).asFuture()
    }
}

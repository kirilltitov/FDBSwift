import CFDB

internal extension FDB.Transaction {
    internal func commit() throws -> Future<Void> {
        return fdb_transaction_commit(self.pointer).asFuture()
    }

    internal func set(key: AnyFDBKey, value: Bytes) {
        let keyBytes = key.asFDBKey()
        fdb_transaction_set(self.pointer, keyBytes, keyBytes.length, value, value.length)
    }

    internal func get(key: AnyFDBKey, snapshot: Bool = false) -> Future<Bytes?> {
        let keyBytes = key.asFDBKey()
        return fdb_transaction_get(self.pointer, keyBytes, keyBytes.length, snapshot.int).asFuture()
    }

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
    ) -> Future<FDB.KeyValuesResult> {
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
    ) -> Future<FDB.KeyValuesResult> {
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

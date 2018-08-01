import CFDB

public extension Transaction {
    public func commit() throws -> Future<Void> {
        let future: Future<Void> = fdb_transaction_commit(self.pointer).asFuture()
        try future.whenReady { _future in
            let commitError = fdb_future_get_error(future.pointer)
            guard commitError == 0 else {
                throw FDB.Error.from(errno: commitError)
            }
        }
        return future
    }

    public func set(key: FDBKey, value: Bytes) {
        let keyBytes = key.asFDBKey()
        fdb_transaction_set(self.pointer, keyBytes, keyBytes.length, value, value.length)
    }

    public func get(
        begin: FDBKey,
        end: FDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false
    ) -> Future<KeyValuesResult> {
        let beginBytes = begin.asFDBKey()
        let endBytes = end.asFDBKey()
        return fdb_transaction_get_range(
            self.pointer,
            beginBytes, beginBytes.length, beginEqual.int, beginOffset,
            endBytes, endBytes.length, endEqual.int, endOffset,
            limit,
            targetBytes,
            FDBStreamingMode(mode.rawValue),
            iteration,
            snapshot,
            reverse.int
        ).asFuture()
    }

    public func get(
        range: RangeFDBKey,
        beginEqual: Bool = false,
        beginOffset: Int32 = 1,
        endEqual: Bool = false,
        endOffset: Int32 = 1,
        limit: Int32 = 0,
        targetBytes: Int32 = 0,
        mode: FDB.StreamingMode = .WantAll,
        iteration: Int32 = 1,
        snapshot: Int32 = 0,
        reverse: Bool = false
    ) -> Future<KeyValuesResult> {
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

    public func get(key: FDBKey, snapshot: Int32 = 0) -> Future<Bytes?> {
        let keyBytes = key.asFDBKey()
        return fdb_transaction_get(self.pointer, keyBytes, keyBytes.length, snapshot).asFuture()
    }
}

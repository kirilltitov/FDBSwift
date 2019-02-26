import CFDB

internal extension FDB.Transaction {
    internal func commit() throws -> Future<Void> {
        return fdb_transaction_commit(self.pointer).asFuture()
    }

    internal func set(key: AnyFDBKey, value: Bytes) {
        let keyBytes = key.asFDBKey()
        fdb_transaction_set(self.pointer, keyBytes, keyBytes.length, value, value.length)
    }

    internal func get(key: AnyFDBKey, snapshot: Int32 = 0) -> Future<Bytes?> {
        let keyBytes = key.asFDBKey()
        return fdb_transaction_get(self.pointer, keyBytes, keyBytes.length, snapshot).asFuture()
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
        snapshot: Int32 = 0,
        reverse: Bool = false
    ) -> Future<FDB.KeyValuesResult> {
        let beginBytes = begin.asFDBKey()
        let endBytes = end.asFDBKey()
        
        self.debug("""
        Calling C function fdb_transaction_get_range(
            FDBTransaction* tr: \(self.pointer)
            uint8_t const* begin_key_name: \(beginBytes)
            int begin_key_name_length: \(beginBytes.length)
            fdb_bool_t begin_or_equal: \(beginEqual.int)
            int begin_offset: \(beginOffset)
            uint8_t const* end_key_name: \(endBytes)
            int end_key_name_length: \(endBytes.length)
            fdb_bool_t end_or_equal: \(endEqual.int)
            int end_offset: \(endOffset)
            int limit: \(limit)
            int target_bytes: \(targetBytes)
            FDBStreamingMode mode: \(FDBStreamingMode(mode.rawValue))
            int iteration: \(iteration)
            fdb_bool_t snapshot: \(snapshot)
            fdb_bool_t reverse: \(reverse.int)
        )
        """)
        
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
            snapshot,
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
        snapshot: Int32 = 0,
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

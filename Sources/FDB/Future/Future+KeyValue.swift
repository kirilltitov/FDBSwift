import CFDB

extension FDB.Future {
    /// Parses key values result from current future
    ///
    /// Warning: this should be only called if future is in resolved state
    @inlinable
    internal func parseKeyValues() throws -> FDB.KeyValuesResult {
        var outRawValues: UnsafePointer<FDBKeyValue>!
        var outCount: Int32 = 0
        var outMore: Int32 = 0

        try fdb_future_get_keyvalue_array(self.pointer, &outRawValues, &outCount, &outMore).orThrow()

        var records: [FDB.KeyValue] = []
        if outCount > 0 {
            // `FDBKeyValue` is declared with `#pragma pack(4)` in `fdb_c.h`, so its array is not guaranteed
            // to be aligned the way Swift expects. Each element is read with an unaligned load instead of
            // rebinding/dereferencing the typed pointer (which traps on recent toolchains, see issue #86).
            let raw = UnsafeRawPointer(outRawValues!)
            let stride = MemoryLayout<FDBKeyValue>.stride
            records.reserveCapacity(Int(outCount))
            for i in 0 ..< Int(outCount) {
                let kv = raw.loadUnaligned(fromByteOffset: i * stride, as: FDBKeyValue.self)
                records.append(
                    FDB.KeyValue(
                        key: kv.key.getBytes(count: kv.key_length),
                        value: kv.value.getBytes(count: kv.value_length)
                    )
                )
            }
        }

        return FDB.KeyValuesResult(records: records, hasMore: outMore > 0)
    }
}

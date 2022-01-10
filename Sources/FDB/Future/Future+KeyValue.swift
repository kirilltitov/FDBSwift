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

        return FDB.KeyValuesResult(
            records: outCount == 0 ? [] : outRawValues.unwrapPointee(count: outCount).map {
                FDB.KeyValue(
                    key: $0.key.getBytes(count: $0.key_length),
                    value: $0.value.getBytes(count: $0.value_length)
                )
            },
            hasMore: outMore > 0
        )
    }
}

import CFDB

fileprivate class KeyValueArrayContext {
    internal typealias Closure = Future<FDB.KeyValuesResult>.ReadyKeyValuesClosure

    internal let callback: Closure
    internal let ctx: Future<FDB.KeyValuesResult>

    internal init(
        _ callback: @escaping Closure,
        _ ctx: Future<FDB.KeyValuesResult>
    ) {
        self.callback = callback
        self.ctx = ctx
    }
}

internal extension Future where R == FDB.KeyValuesResult {
    internal typealias ReadyKeyValuesClosure = (_ result: FDB.KeyValuesResult) throws -> Void

    internal func whenReady(_ callback: @escaping ReadyKeyValuesClosure) throws {
        try fdb_future_set_callback(
            self.pointer,
            { futurePtr, contextPtr in
                let context = Unmanaged<KeyValueArrayContext>.fromOpaque(contextPtr!).takeRetainedValue()
                do {
                    let result = try context.ctx.parseKeyValues(futurePtr!)
                    try context.callback(result)
                } catch {
                    context.ctx.fail(with: error)
                }
            },
            Unmanaged<KeyValueArrayContext>.passRetained(KeyValueArrayContext(callback, self)).toOpaque()
        ).orThrow()
    }

    internal func wait() throws -> FDB.KeyValuesResult {
        return try self.waitAndCheck().parseKeyValues(self.pointer)
    }

    internal func parseKeyValues(_ futurePtr: OpaquePointer) throws -> FDB.KeyValuesResult {
        var outRawValues: UnsafePointer<FDBKeyValue>!
        var outCount: Int32 = 0
        var outMore: Int32 = 0

        try fdb_future_get_keyvalue_array(futurePtr, &outRawValues, &outCount, &outMore).orThrow()

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

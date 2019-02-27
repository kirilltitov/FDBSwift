import CFDB

/// A context wrapper (box) for passing to a CFDB function as `*void`
fileprivate class KeyValueArrayContext {
    internal typealias Closure = FDB.Future<FDB.KeyValuesResult>.ReadyKeyValuesClosure

    internal let callback: Closure
    internal let ctx: FDB.Future<FDB.KeyValuesResult>

    internal init(
        _ callback: @escaping Closure,
        _ ctx: FDB.Future<FDB.KeyValuesResult>
    ) {
        self.callback = callback
        self.ctx = ctx
    }
}

internal extension FDB.Future where R == FDB.KeyValuesResult {
    internal typealias ReadyKeyValuesClosure = (_ result: FDB.KeyValuesResult) throws -> Void

    /// Sets a closure to be executed when current future is resolved
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

    /// Blocks current thread until future is resolved
    internal func wait() throws -> FDB.KeyValuesResult {
        return try self.waitAndCheck().parseKeyValues(self.pointer)
    }

    /// Parses key values result from current future
    ///
    /// Warning: this should be only called if future is in resolved state
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

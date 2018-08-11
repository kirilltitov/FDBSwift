import CFDB

fileprivate class KeyValueArrayContext {
    typealias Closure = Future<KeyValuesResult>.ReadyKeyValuesClosure

    let callback: Closure
    let ctx: Future<KeyValuesResult>
    
    init(
        _ callback: @escaping Closure,
        _ ctx: Future<KeyValuesResult>
    ) {
        self.callback = callback
        self.ctx = ctx
    }
}

public extension Future where R == KeyValuesResult {
    public typealias ReadyKeyValuesClosure = (_ result: KeyValuesResult) throws -> Void

    public func whenReady(_ callback: @escaping ReadyKeyValuesClosure) throws {
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

    public func wait() throws -> KeyValuesResult {
        return try self.waitAndCheck().parseKeyValues(self.pointer)
    }

    internal func parseKeyValues(_ futurePtr: OpaquePointer) throws -> KeyValuesResult {
        var outRawValues: UnsafePointer<FDBKeyValue>!
        var outCount: Int32 = 0
        var outMore: Int32 = 0

        try fdb_future_get_keyvalue_array(futurePtr, &outRawValues, &outCount, &outMore).orThrow()

        return KeyValuesResult(
            records: outCount == 0 ? [] : outRawValues.unwrapPointee(count: outCount).map {
                return KeyValue(
                    key: $0.key.getBytes(count: $0.key_length),
                    value: $0.value.getBytes(count: $0.value_length)
                )
            },
            hasMore: outMore > 0
        )
    }
}

import CFDB

fileprivate class KeyValueArrayContext {
    let callback: (_ values: [KeyValue], _ more: Bool) -> Void
    
    init(_ callback: @escaping (_ values: [KeyValue], _ more: Bool) -> Void) {
        self.callback = callback
    }
}

public extension Future where R == [KeyValue] {
    public func whenReady(_ callback: @escaping (_ bytes: [KeyValue], _ more: Bool) -> Void) throws {
        try fdb_future_set_callback(
            self.pointer,
            { futurePtr, contextPtr in
                let callback = Unmanaged<KeyValueArrayContext>.fromOpaque(contextPtr!).takeRetainedValue().callback
                
                var outRawValues: UnsafePointer<FDBKeyValue>!
                var outCount: Int32 = 0
                var outMore: Int32 = 0

                do {
                    try fdb_future_get_keyvalue_array(futurePtr, &outRawValues, &outCount, &outMore).orThrow()
                } catch {
                    print("FDB: Unexpected error occured while unwrapping [KeyValue] future: \(error)")
                    callback([], false)
                    return
                }

                callback(
                    outCount == 0 ? [] : outRawValues.unwrapPointee(count: outCount).map {
                        return KeyValue(
                            key: $0.key.getBytes(count: $0.key_length),
                            value: $0.value.getBytes(count: $0.value_length)
                        )
                    },
                    outMore > 0
                )
            },
            Unmanaged<KeyValueArrayContext>.passUnretained(KeyValueArrayContext(callback)).toOpaque()
        ).orThrow()
    }
}

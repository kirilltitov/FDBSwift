import CFDB

fileprivate class BytesContext {
    let callback: (_ bytes: Bytes?) -> Void
    
    init(_ callback: @escaping (_ bytes: Bytes?) -> Void) {
        self.callback = callback
    }
}

public extension Future where R == Bytes? {
    public func whenReady(_ callback: @escaping (_ bytes: Bytes?) -> Void) throws {
        try fdb_future_set_callback(
            self.pointer,
            { futurePtr, contextPtr in
                let callback = Unmanaged<BytesContext>.fromOpaque(contextPtr!).takeRetainedValue().callback

                var readValueFound: Int32 = 0
                var readValue: UnsafePointer<Byte>!
                var readValueLength: Int32 = 0

                do {
                    try fdb_future_get_value(futurePtr, &readValueFound, &readValue, &readValueLength).orThrow()
                } catch {
                    print("FDB: Unexpected error occured while unwrapping Bytes future: \(error)")
                    callback(nil)
                    return
                }

                guard readValueFound > 0 else {
                    callback(nil)
                    return
                }
                callback(readValue.getBytes(count: readValueLength))
            },
            Unmanaged<BytesContext>.passUnretained(BytesContext(callback)).toOpaque()
        ).orThrow()
    }
}

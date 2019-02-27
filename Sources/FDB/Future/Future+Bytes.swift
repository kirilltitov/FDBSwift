import CFDB

/// A context wrapper (box) for passing to a CFDB function as `*void`
fileprivate class BytesContext {
    internal typealias Closure = FDB.Future<Bytes?>.ReadyBytesClosure

    internal let callback: Closure
    internal let ctx: FDB.Future<Bytes?>

    init(
        _ callback: @escaping Closure,
        _ ctx: FDB.Future<Bytes?>
    ) {
        self.callback = callback
        self.ctx = ctx
    }
}

internal extension FDB.Future where R == Bytes? {
    internal typealias ReadyBytesClosure = (_ bytes: Bytes?) throws -> Void

    /// Sets a closure to be executed when current future is resolved
    internal func whenReady(_ callback: @escaping ReadyBytesClosure) throws {
        try fdb_future_set_callback(
            self.pointer,
            { futurePtr, contextPtr in
                let context = Unmanaged<BytesContext>.fromOpaque(contextPtr!).takeRetainedValue()
                do {
                    try context.callback(try context.ctx.parseBytes(futurePtr!))
                } catch {
                    context.ctx.fail(with: error)
                }
            },
            Unmanaged<BytesContext>.passRetained(BytesContext(callback, self)).toOpaque()
        ).orThrow()
    }

    /// Blocks current thread until future is resolved
    internal func wait() throws -> Bytes? {
        return try self.waitAndCheck().parseBytes(self.pointer)
    }

    /// Parses bytes result from current future
    ///
    /// Warning: this should be only called if future is in resolved state
    internal func parseBytes(_ futurePtr: OpaquePointer) throws -> Bytes? {
        var readValueFound: Int32 = 0
        var readValue: UnsafePointer<Byte>!
        var readValueLength: Int32 = 0

        try fdb_future_get_value(futurePtr, &readValueFound, &readValue, &readValueLength).orThrow()

        guard readValueFound > 0 else {
            return nil
        }

        return readValue.getBytes(count: readValueLength)
    }
}

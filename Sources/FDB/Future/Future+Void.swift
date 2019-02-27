import CFDB

/// A context wrapper (box) for passing to a CFDB function as `*void`
fileprivate class VoidContext {
    internal typealias Closure = FDB.Future<Void>.ReadyVoidClosure

    internal let callback: Closure
    internal let ctx: FDB.Future<Void>

    internal init(
        _ callback: @escaping Closure,
        _ ctx: FDB.Future<Void>
    ) {
        self.callback = callback
        self.ctx = ctx
    }
}

internal extension FDB.Future where R == Void {
    internal typealias ReadyVoidClosure = (_ future: FDB.Future<Void>) throws -> Void

    /// Sets a closure to be executed when current future is resolved
    internal func whenReady(_ callback: @escaping ReadyVoidClosure) throws {
        try fdb_future_set_callback(
            self.pointer,
            { _, contextPtr in
                let context = Unmanaged<VoidContext>.fromOpaque(contextPtr!).takeRetainedValue()
                do {
                    try context.callback(context.ctx)
                } catch {
                    context.ctx.fail(with: error)
                }
            },
            Unmanaged<VoidContext>.passRetained(VoidContext(callback, self)).toOpaque()
        ).orThrow()
    }
}

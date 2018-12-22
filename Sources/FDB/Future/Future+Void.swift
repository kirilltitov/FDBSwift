import CFDB

fileprivate class VoidContext {
    internal typealias Closure = Future<Void>.ReadyVoidClosure

    internal let callback: Closure
    internal let ctx: Future<Void>

    internal init(
        _ callback: @escaping Closure,
        _ ctx: Future<Void>
    ) {
        self.callback = callback
        self.ctx = ctx
    }
}

internal extension Future where R == Void {
    internal typealias ReadyVoidClosure = (_ future: Future<Void>) throws -> Void

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

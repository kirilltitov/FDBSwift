import CFDB

fileprivate class VoidContext {
    typealias Closure = Future<Void>.ReadyVoidClosure

    let callback: Closure
    let ctx: Future<Void>
    
    init(
        _ callback: @escaping Closure,
        _ ctx: Future<Void>
    ) {
        self.callback = callback
        self.ctx = ctx
    }
}

public extension Future where R == Void {
    public typealias ReadyVoidClosure = (_ future: Future<Void>) throws -> Void

    public func whenReady(_ callback: @escaping ReadyVoidClosure) throws {
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

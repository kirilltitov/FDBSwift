import CFDB

fileprivate class VoidContext {
    let callback: (_ future: Future<Void>) -> Void
    
    init(_ callback: @escaping (_ future: Future<Void>) -> Void) {
        self.callback = callback
    }
}

public extension Future where R == Void {
    public func whenReady(_ callback: @escaping (_ future: Future<Void>) -> Void) throws {
        try fdb_future_set_callback(
            self.pointer,
            { futurePtr, contextPtr in
                Unmanaged<VoidContext>.fromOpaque(contextPtr!).takeRetainedValue().callback(futurePtr!.asFuture())
            },
            Unmanaged<VoidContext>.passUnretained(VoidContext(callback)).toOpaque()
        ).orThrow()
    }
}

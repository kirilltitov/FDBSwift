import CFDB

extension FDB.Future {
    /// Sets a closure to be executed when current future is resolved
    func whenVoidReady(_ callback: @escaping () -> Void) {
        self.whenReady { _ in callback() }
    }
}

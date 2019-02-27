internal extension OpaquePointer {
    /// Creates an FDB.Future from current pointer
    internal func asFuture<R>() -> FDB.Future<R> {
        return FDB.Future<R>(self)
    }

    /// Creates an FDB.Future from current pointer and blocks current thread until future is resolved (or failed)
    @discardableResult internal func waitForFuture<R>() throws -> FDB.Future<R> {
        return try self.asFuture().waitAndCheck()
    }
}

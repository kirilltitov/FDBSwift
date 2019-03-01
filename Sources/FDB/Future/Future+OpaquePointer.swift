internal extension OpaquePointer {
    /// Creates an FDB.Future from current pointer
    internal func asFuture<R>(isTransaction: Bool = true) -> FDB.Future<R> {
        return FDB.Future<R>(self, isTransaction)
    }

    /// Creates an FDB.Future from current pointer and blocks current thread until future is resolved (or failed)
    @discardableResult internal func waitForFuture<R>(isTransaction: Bool = true) throws -> FDB.Future<R> {
        return try self
            .asFuture(isTransaction: isTransaction)
            .waitAndCheck()
    }
}

internal extension OpaquePointer {
    /// Creates an FDB.Future from current pointer
    func asFuture() -> FDB.Future {
        return FDB.Future(self)
    }

    /// Creates an FDB.Future from current pointer and blocks current thread until future is resolved (or failed)
    @discardableResult func waitForFuture() throws -> FDB.Future {
        return try self
            .asFuture()
            .waitAndCheck()
    }
}

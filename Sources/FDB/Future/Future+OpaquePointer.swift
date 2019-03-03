internal extension OpaquePointer {
    /// Creates an FDB.Future from current pointer
    func asFuture(isTransaction: Bool = true) -> FDB.Future {
        return FDB.Future(self, isTransaction)
    }

    /// Creates an FDB.Future from current pointer and blocks current thread until future is resolved (or failed)
    @discardableResult func waitForFuture(isTransaction: Bool = true) throws -> FDB.Future {
        return try self
            .asFuture(isTransaction: isTransaction)
            .waitAndCheck()
    }
}

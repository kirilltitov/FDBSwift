internal extension OpaquePointer {
    internal func asFuture<R>() -> Future<R> {
        return Future<R>(self)
    }

    @discardableResult internal func waitForFuture<R>() throws -> Future<R> {
        return try self.asFuture().waitAndCheck()
    }
}

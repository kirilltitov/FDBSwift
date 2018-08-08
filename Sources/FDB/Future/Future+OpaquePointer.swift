internal extension OpaquePointer {
    func asFuture<R>() -> Future<R> {
        return Future<R>(self)
    }

    @discardableResult func waitForFuture<R>() throws -> Future<R> {
        return try self.asFuture().waitAndCheck()
    }
}

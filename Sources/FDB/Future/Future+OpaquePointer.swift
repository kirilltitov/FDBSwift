internal extension OpaquePointer {
    /// Creates an FDB.Future from current pointer
    func asFuture(ref: Any? = nil) -> FDB.Future {
        FDB.Future(self, ref)
    }
}

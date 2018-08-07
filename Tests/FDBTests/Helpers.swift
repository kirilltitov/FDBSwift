import FDB

fileprivate extension Array where Element == Byte {
    func cast<Result>() -> Result {
        precondition(
            MemoryLayout<Result>.size == self.count,
            "Memory layout size for result type '\(Result.self)' (\(MemoryLayout<Result>.size) bytes) does not match with given byte array length (\(self.count) bytes)"
        )
        return self.withUnsafeBytes {
            $0.baseAddress!.assumingMemoryBound(to: Result.self).pointee
        }
    }
}

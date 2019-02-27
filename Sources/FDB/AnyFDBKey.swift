public extension FDB {
    /// Holds begin and end keys for range get
    public typealias RangeKey = (begin: AnyFDBKey, end: AnyFDBKey)
}

/// A type-erased FDB key
public protocol AnyFDBKey: FDBTuplePackable {
    /// Returns byte representation of this concrete key
    func asFDBKey() -> Bytes
}

public extension AnyFDBKey {
    public func pack() -> Bytes {
        return self.asFDBKey().pack()
    }
}

extension String: AnyFDBKey {
    public func asFDBKey() -> Bytes {
        return Bytes(self.utf8)
    }
}

extension StaticString: AnyFDBKey {
    public func asFDBKey() -> Bytes {
        return self.utf8Start.getBytes(count: Int32(self.utf8CodeUnitCount))
    }
}

extension Array: AnyFDBKey where Element == Byte {
    public func asFDBKey() -> Bytes {
        return self
    }
}

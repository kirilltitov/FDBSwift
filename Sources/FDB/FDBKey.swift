public extension FDB {
    public typealias RangeKey = (begin: FDBKey, end: FDBKey)
}

// todo rename to AnyFDBKey
public protocol FDBKey: FDBTuplePackable {
    func asFDBKey() -> Bytes
}

public extension FDBKey {
    public func pack() -> Bytes {
        return self.asFDBKey().pack()
    }
}

extension String: FDBKey {
    public func asFDBKey() -> Bytes {
        return Bytes(self.utf8)
    }
}

extension StaticString: FDBKey {
    public func asFDBKey() -> Bytes {
        return self.utf8Start.getBytes(count: Int32(self.utf8CodeUnitCount))
    }
}

extension Array: FDBKey where Element == Byte {
    public func asFDBKey() -> Bytes {
        return self
    }
}

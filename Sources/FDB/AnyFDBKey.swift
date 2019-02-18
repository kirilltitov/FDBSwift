public extension FDB {
    public typealias RangeKey = (begin: AnyFDBKey, end: AnyFDBKey)
}

public protocol AnyFDBKey: FDBTuplePackable {
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

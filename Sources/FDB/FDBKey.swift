public typealias RangeFDBKey = (begin: FDBKey, end: FDBKey)

public protocol FDBKey: TuplePackable {
    func asFDBKey() -> Bytes
}

extension FDBKey {
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

extension Tuple: FDBKey {
    public func asFDBKey() -> Bytes {
        return self.pack()
    }
}

extension Subspace: FDBKey {
    public func asFDBKey() -> Bytes {
        return self.prefix
    }
}

extension Array: FDBKey where Element == Byte {
    public func asFDBKey() -> Bytes {
        return self
    }
}

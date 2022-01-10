public extension FDB {
    /// Holds begin and end keys for range get
    typealias RangeKey = (begin: AnyFDBKey, end: AnyFDBKey)
}

/// A type-erased FDB key
public protocol AnyFDBKey: FDBTuplePackable {
    /// Returns byte representation of this concrete key
    func asFDBKey() -> Bytes
}

public extension AnyFDBKey {
    func getPackedFDBTupleValue() -> Bytes {
        self.asFDBKey().getPackedFDBTupleValue()
    }
}

extension String: AnyFDBKey {
    public func asFDBKey() -> Bytes {
        Bytes(self.utf8)
    }
}

extension StaticString: AnyFDBKey {
    public func asFDBKey() -> Bytes {
        self.utf8Start.getBytes(count: Int32(self.utf8CodeUnitCount))
    }
}

extension Bytes: AnyFDBKey {
    public func asFDBKey() -> Bytes {
        self
    }
}

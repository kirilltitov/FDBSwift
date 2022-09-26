public extension FDB {
    /// Holds begin and end keys for range get
    typealias RangeKey = (begin: any FDBKey, end: any FDBKey)
}

/// A type-erased FDB key
public protocol FDBKey: FDBTuplePackable {
    /// Returns byte representation of this concrete key
    func asFDBKey() -> Bytes
}

public extension FDBKey {
    func getPackedFDBTupleValue() -> Bytes {
        self.asFDBKey().getPackedFDBTupleValue()
    }
}

extension String: FDBKey {
    public func asFDBKey() -> Bytes {
        Bytes(self.utf8)
    }
}

extension StaticString: FDBKey {
    public func asFDBKey() -> Bytes {
        self.utf8Start.getBytes(count: Int32(self.utf8CodeUnitCount))
    }
}

extension Bytes: FDBKey {
    public func asFDBKey() -> Bytes {
        self
    }
}

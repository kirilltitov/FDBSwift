public typealias RangeFDBKey = (begin: FDBKey, end: FDBKey)

public struct KeyValue {
    public let key: Bytes
    public let value: Bytes
}

extension KeyValue: Equatable {
    public static func == (lhs: KeyValue, rhs: KeyValue) -> Bool {
        return lhs.key == rhs.key && lhs.value == rhs.value
    }
}

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

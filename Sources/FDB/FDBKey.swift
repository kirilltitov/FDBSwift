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

public protocol FDBKey {
    func asFDBKey() -> Bytes
    func asFDBKeyLength() -> Int32
}

extension String: FDBKey {
    public func asFDBKey() -> Bytes {
        return Bytes(self.utf8)
    }

    public func asFDBKeyLength() -> Int32 {
        return Int32(self.count)
    }
}

extension Tuple: FDBKey {
    public func asFDBKey() -> Bytes {
        return self.pack()
    }

    public func asFDBKeyLength() -> Int32 {
        // not really good solution
        return Int32(self.pack().count)
    }
}

extension Subspace: FDBKey {
    public func asFDBKey() -> Bytes {
        return self.prefix
    }

    public func asFDBKeyLength() -> Int32 {
        return Int32(self.prefix.count)
    }
}

extension Array: FDBKey where Element == Byte {
    public func asFDBKey() -> Bytes {
        return self
    }

    public func asFDBKeyLength() -> Int32 {
        return Int32(self.count)
    }
}

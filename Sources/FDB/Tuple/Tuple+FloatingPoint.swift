@inlinable internal func transformFloatingPoint(bytes: inout Bytes, start: Int, encode: Bool) {
    if encode && (bytes[start] & 0x80) != 0x00 {
        for i in start ..< bytes.count {
            bytes[i] = bytes[i] ^ 0xff
        }
    } else if !encode && (bytes[start] & 0x80) != 0x80 {
        for i in start ..< bytes.count {
            bytes[i] = bytes[i] ^ 0xff
        }
    } else {
        bytes[start] = 0x80 ^ bytes[start]
    }
}

extension Float32: FDBTuplePackable {
    public func pack() -> Bytes {
        var result = Bytes([FDB.Tuple.Prefix.FLOAT])
        result.append(contentsOf: getBytes(self))
        transformFloatingPoint(bytes: &result, start: 1, encode: true)
        return result
    }
}

extension Double: FDBTuplePackable {
    public func pack() -> Bytes {
        var result = Bytes([FDB.Tuple.Prefix.DOUBLE])
        result.append(contentsOf: getBytes(self))
        transformFloatingPoint(bytes: &result, start: 1, encode: true)
        return result
    }
}

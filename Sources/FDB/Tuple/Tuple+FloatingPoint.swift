@inlinable
internal func transformFloatingPoint(bytes: inout Bytes, start: Int, encode: Bool) {
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

@inlinable
internal func getGenericFloatFDBTupleValue(input: Bytes, prefix: Byte) -> Bytes {
    var result = Bytes([prefix])

    result.append(contentsOf: input)
    transformFloatingPoint(bytes: &result, start: 1, encode: true)

    return result
}

extension Float32: FDBTuplePackable {
    public func getPackedFDBTupleValue() -> Bytes {
        getGenericFloatFDBTupleValue(input: getBytes(self), prefix: FDB.Tuple.Prefix.FLOAT)
    }
}

extension Double: FDBTuplePackable {
    public func getPackedFDBTupleValue() -> Bytes {
        getGenericFloatFDBTupleValue(input: getBytes(self), prefix: FDB.Tuple.Prefix.DOUBLE)
    }
}

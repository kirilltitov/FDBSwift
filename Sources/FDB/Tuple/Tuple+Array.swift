/// Packs input bytes as BYTE STRING tuple value with null bytes escaping preprocessing
@usableFromInline
internal func packBytes(_ bytes: Bytes) -> Bytes {
    var result = Bytes()

    result.append(FDB.Tuple.Prefix.BYTE_STRING)
    bytes.forEach {
        if $0 == FDB.Tuple.NULL {
            result.append(contentsOf: FDB.Tuple.NULL_ESCAPE_SEQUENCE)
        } else {
            result.append($0)
        }
    }
    result.append(FDB.Tuple.NULL)

    return result
}

extension Bytes: FDBTuplePackable {
    public func getPackedFDBTupleValue() -> Bytes {
        packBytes(self)
    }
}

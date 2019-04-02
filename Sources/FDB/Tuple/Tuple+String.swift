extension String: FDBTuplePackable {
    public func pack() -> Bytes {
        let bytes = Bytes(self.utf8)
        var result = Bytes()
        result.append(FDB.Tuple.Prefix.UTF_STRING)
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
}

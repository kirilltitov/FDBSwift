extension Bool: FDBTuplePackable {
    public func pack() -> Bytes {
        return self
            ? [FDB.Tuple.Prefix.BOOL_TRUE]
            : [FDB.Tuple.Prefix.BOOL_FALSE]
    }
}

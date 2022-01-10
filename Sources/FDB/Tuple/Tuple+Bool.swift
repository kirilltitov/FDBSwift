extension Bool: FDBTuplePackable {
    public func getPackedFDBTupleValue() -> Bytes {
        self
            ? [FDB.Tuple.Prefix.BOOL_TRUE]
            : [FDB.Tuple.Prefix.BOOL_FALSE]
    }
}
